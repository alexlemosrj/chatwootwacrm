require 'rails_helper'

RSpec.describe 'CRM account and pipeline integrity', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal) { account.deals.create!(pipeline: pipeline, pipeline_stage: pipeline.pipeline_stages.first, title: 'Protected deal') }

  it 'completes the account deletion job in dependency order' do
    contact = create(:contact, account: account)
    deal.update!(contact: contact)
    activity = account.crm_activities.create!(deal: deal, contact: contact, title: 'History', activity_type: 'task')
    event = account.crm_events.create!(deal: deal, contact: contact, actor: admin, event_type: 'history')
    other_account = create(:account)

    DeleteObjectJob.perform_now(account)

    expect(Account.exists?(account.id)).to be(false)
    expect([deal, activity, event, pipeline, contact].map { |record| record.class.exists?(record.id) }).to all(be(false))
    expect(PipelineStage.where(pipeline_id: pipeline.id)).not_to exist
    expect(Account.exists?(other_account.id)).to be(true)
    expect(other_account.pipelines).to exist
  end

  it 'deletes an empty pipeline and its stages through the API' do
    empty_pipeline = account.pipelines.create!(name: 'Empty')
    stage = empty_pipeline.pipeline_stages.create!(name: 'Entry', position: 0)
    delete "/api/v1/accounts/#{account.id}/pipelines/#{empty_pipeline.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Pipeline.exists?(empty_pipeline.id)).to be(false)
    expect(PipelineStage.exists?(stage.id)).to be(false)
  end

  it 'preserves database cascade from pipeline to stages' do
    stage_ids = pipeline.pipeline_stages.ids
    pipeline.delete

    expect(PipelineStage.where(id: stage_ids)).not_to exist
  end

  it 'protects pipelines and their stages when deals exist' do
    deal
    stage_ids = pipeline.pipeline_stages.ids
    delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(deal.reload.pipeline_id).to eq(pipeline.id)
    expect(pipeline.pipeline_stages.ids).to eq(stage_ids)
  end
end
