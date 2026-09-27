require 'rails_helper'

RSpec.describe 'CRM agent integrity', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal) do
    account.deals.create!(assignee: agent, pipeline: pipeline, pipeline_stage: pipeline.pipeline_stages.first, title: 'Assigned deal')
  end
  let(:activity) { account.crm_activities.create!(assignee: agent, title: 'Assigned activity', activity_type: 'task') }
  let(:event) { account.crm_events.create!(actor: agent, event_type: 'agent_history', metadata: { note: 'Preserve history' }) }

  it 'clears only the removed account assignments and preserves historical authorship' do
    other_account = create(:account)
    create(:account_user, account: other_account, user: agent)
    other_activity = other_account.crm_activities.create!(assignee: agent, title: 'Other account', activity_type: 'task')
    conversation = create(:conversation, account: account, assignee: agent)
    records = [deal, activity, event]
    snapshots = records.map(&:attributes)

    expect do
      delete "/api/v1/accounts/#{account.id}/agents/#{agent.id}", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(Agents::DestroyJob).with(account, agent)
    expect(response).to have_http_status(:ok)
    expect(DeleteObjectJob).not_to have_been_enqueued
    perform_enqueued_jobs(only: Agents::DestroyJob)

    expect(account.account_users.where(user: agent)).not_to exist
    expect(other_account.account_users.where(user: agent)).to exist
    expect(User.exists?(agent.id)).to be(true)
    expect(conversation.reload.assignee_id).to be_nil
    expect(deal.reload.assignee_id).to be_nil
    expect(activity.reload.assignee_id).to be_nil
    expect(event.reload.attributes).to eq(snapshots.last)
    expect(other_activity.reload.assignee_id).to eq(agent.id)
    expect([deal, activity, event]).to all(be_valid)
  end

  it 'removes the last membership and user while preserving all CRM history' do
    records = [deal, activity, event]
    snapshots = records.map(&:attributes)

    expect do
      delete "/api/v1/accounts/#{account.id}/agents/#{agent.id}", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(DeleteObjectJob).with(agent)
    expect(response).to have_http_status(:ok)
    perform_enqueued_jobs(only: Agents::DestroyJob)

    perform_enqueued_jobs(only: DeleteObjectJob)

    expect(User.exists?(agent.id)).to be(false)
    expect(deal.reload.assignee_id).to be_nil
    expect(activity.reload.assignee_id).to be_nil
    expect(event.reload.actor_id).to be_nil
    expect(event.actor_snapshot).to eq(snapshots.last.fetch('actor_snapshot'))
    expect(event.metadata).to eq(snapshots.last.fetch('metadata'))
    expect(records).to all(be_valid)

    get "/api/v1/accounts/#{account.id}/crm_events", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    historical_event = response.parsed_body.fetch('payload').find { |item| item['id'] == event.id }
    expect(historical_event.fetch('actor')).to eq(event.actor_snapshot)
  end

  {
    'Deal assignee' => [:deal],
    'Activity assignee' => [:activity],
    'Event actor' => [:event],
    'all CRM user references' => [:deal, :activity, :event]
  }.each do |label, references|
    context "with #{label}" do
      let!(:crm_records) { references.map { |reference| public_send(reference) } }

      it 'deletes the platform user and preserves CRM records and actor snapshots' do
        platform_app = create(:platform_app)
        create(:platform_app_permissible, platform_app: platform_app, permissible: agent)
        conversation = create(:conversation, account: account, assignee: agent)
        snapshots = crm_records.map(&:attributes)

        expect do
          delete "/platform/api/v1/users/#{agent.id}", headers: { api_access_token: platform_app.access_token.token }, as: :json
        end.to have_enqueued_job(DeleteObjectJob).with(agent)
        expect(response).to have_http_status(:ok)

        perform_enqueued_jobs(only: DeleteObjectJob)

        expect(User.exists?(agent.id)).to be(false)
        crm_records.zip(snapshots).each do |record, snapshot|
          changed_reference = record.is_a?(CrmEvent) ? 'actor_id' : 'assignee_id'
          expect(record.reload.attributes).to eq(snapshot.merge(changed_reference => nil))
        end
        expect(conversation.reload.assignee_id).to be_nil
      end
    end
  end

  it 'rejects new authorship by a user outside the account' do
    outsider = create(:user)
    invalid_event = account.crm_events.new(actor: outsider, event_type: 'invalid_actor')

    expect(invalid_event).not_to be_valid
    expect(invalid_event.errors[:actor]).to include('must belong to the same account')
  end

  it 'retains the original snapshot when the author changes name and is deleted directly' do
    snapshot = event.actor_snapshot
    agent.update!(name: 'Renamed author')
    records = [deal, activity]
    agent.delete

    expect(event.reload.actor_id).to be_nil
    expect(event.actor_snapshot).to eq(snapshot)
    expect(records.map { |record| record.reload.assignee_id }).to all(be_nil)
    expect(event.metadata).to eq('note' => 'Preserve history')
  end
end
