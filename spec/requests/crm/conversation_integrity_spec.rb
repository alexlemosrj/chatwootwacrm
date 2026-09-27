require 'rails_helper'

RSpec.describe 'CRM conversation integrity', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal_attributes) do
    {
      title: 'Conversation deal', pipeline_id: pipeline.id, pipeline_stage_id: pipeline.pipeline_stages.first.id,
      contact_id: conversation.contact_id, conversation_id: conversation.id
    }
  end

  it 'persists and filters exclusively by internal id when conversation_id is supplied' do
    create(:conversation)
    expect(conversation.id).not_to eq(conversation.display_id)

    post "/api/v1/accounts/#{account.id}/deals", params: { deal: deal_attributes }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success), response.body
    deal = account.deals.find(response.parsed_body.fetch('id'))
    expect(deal.conversation_id).to eq(conversation.id)

    get "/api/v1/accounts/#{account.id}/deals", params: { conversation_id: conversation.id }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.fetch('payload').pluck('id')).to contain_exactly(deal.id)
    get "/api/v1/accounts/#{account.id}/deals", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.fetch('payload')).to be_empty
  end

  it 'resolves the CE sidebar display id using the explicitly named parameter' do
    conversation.update!(display_id: Conversation.maximum(:id) + 1000)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    sidebar_id = response.parsed_body.fetch('id')
    attributes = deal_attributes.except(:conversation_id).merge(conversation_display_id: sidebar_id)

    post "/api/v1/accounts/#{account.id}/deals", params: { deal: attributes }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success), response.body
    expect(account.deals.last.conversation_id).to eq(conversation.id)
  end

  it 'resolves display id collisions without linking to the other primary key' do
    create(:conversation)
    other_conversation = create(:conversation, account: account)
    conversation.update!(display_id: other_conversation.id)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token, as: :json
    sidebar_id = response.parsed_body.fetch('id')
    attributes = deal_attributes.except(:conversation_id).merge(conversation_display_id: sidebar_id)

    post "/api/v1/accounts/#{account.id}/deals", params: { deal: attributes }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success), response.body
    expect(account.deals.last.conversation_id).to eq(conversation.id)
    expect(account.deals.last.conversation_id).not_to eq(other_conversation.id)
  end

  it 'rejects an internal id from another account' do
    other_conversation = create(:conversation)
    post "/api/v1/accounts/#{account.id}/deals",
         params: { deal: deal_attributes.merge(conversation_id: other_conversation.id) }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.deals).to be_empty
    expect(account.crm_events).to be_empty
  end

  it 'does not resolve display ids outside the current account' do
    other_conversation = create(:conversation)
    other_conversation.update!(display_id: 999_999)
    attributes = deal_attributes.except(:conversation_id).merge(conversation_display_id: other_conversation.display_id)

    post "/api/v1/accounts/#{account.id}/deals", params: { deal: attributes }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.deals).to be_empty
  end

  it 'rejects a missing internal id without falling back to display id' do
    conversation.update!(display_id: Conversation.maximum(:id) + 1000)
    post "/api/v1/accounts/#{account.id}/deals",
         params: { deal: deal_attributes.merge(conversation_id: conversation.display_id) }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.deals).to be_empty
    expect(account.crm_events).to be_empty
  end

  it 'rejects ambiguous parameters even when one is null' do
    post "/api/v1/accounts/#{account.id}/deals",
         params: { deal: deal_attributes.merge(conversation_display_id: nil) }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.deals).to be_empty
  end

  ['12', 1.5, 0, -1, [], {}, true].each do |invalid_id|
    it "rejects malformed conversation identifiers: #{invalid_id.inspect}" do
      post "/api/v1/accounts/#{account.id}/deals",
           params: { deal: deal_attributes.merge(conversation_id: invalid_id) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.deals).to be_empty
    end
  end

  it 'validates updates and allows explicitly unlinking a conversation' do
    deal = account.deals.create!(deal_attributes)
    patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
          params: { deal: { conversation_id: Conversation.maximum(:id) + 1000 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(deal.reload.conversation_id).to eq(conversation.id)

    patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
          params: { deal: { conversation_id: nil } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(deal.reload.conversation_id).to be_nil
  end

  it 'completes the real deletion job and preserves the deal, activities and events' do
    post "/api/v1/accounts/#{account.id}/deals", params: { deal: deal_attributes }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success), response.body
    deal = account.deals.find(response.parsed_body.fetch('id'))
    event = account.crm_events.find_by!(deal: deal)
    activity = account.crm_activities.create!(deal: deal, title: 'Retained activity', activity_type: 'task')
    snapshots = [deal, activity, event].map(&:attributes)

    expect do
      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(DeleteObjectJob).with(conversation, admin, anything)
    expect(response).to have_http_status(:ok)
    perform_enqueued_jobs(only: DeleteObjectJob)

    expect(Conversation.exists?(conversation.id)).to be(false)
    expect(deal.reload.attributes).to eq(snapshots.first.merge('conversation_id' => nil))
    expect([activity, event].map { |record| record.reload.attributes }).to eq(snapshots.last(2))
  end

  it 'nullifies the database FK even when Rails callbacks are bypassed' do
    deal = account.deals.create!(deal_attributes)
    conversation.delete

    expect(deal.reload.conversation_id).to be_nil
    expect(Deal.exists?(deal.id)).to be(true)
  end
end
