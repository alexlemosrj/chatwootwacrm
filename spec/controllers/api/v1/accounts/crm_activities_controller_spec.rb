require 'rails_helper'

RSpec.describe 'CRM Activities API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal) do
    account.deals.create!(
      pipeline: pipeline,
      pipeline_stage: pipeline.pipeline_stages.first,
      title: 'Follow-up'
    )
  end

  it 'creates an activity and a CRM event' do
    post "/api/v1/accounts/#{account.id}/crm_activities",
         params: {
           crm_activity: {
             deal_id: deal.id,
             title: 'Ligar para cliente',
             activity_type: 'call',
             due_at: 1.day.from_now
           }
         },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    activity = account.crm_activities.last
    expect(activity.deal_id).to eq(deal.id)
    expect(account.crm_events.where(deal: deal, event_type: 'activity_created')).to exist
  end

  it 'marks completed_at when completing an activity' do
    activity = account.crm_activities.create!(
      deal: deal,
      title: 'Enviar retorno',
      activity_type: 'followup'
    )

    patch "/api/v1/accounts/#{account.id}/crm_activities/#{activity.id}",
          params: { crm_activity: { status: 'completed' } },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:success)
    expect(activity.reload.status).to eq('completed')
    expect(activity.completed_at).to be_present
  end

  it 'rejects a deal from another account' do
    other_account = create(:account)
    other_pipeline = other_account.pipelines.find_by!(is_default: true)
    foreign_deal = other_account.deals.create!(
      pipeline: other_pipeline,
      pipeline_stage: other_pipeline.pipeline_stages.first,
      title: 'Foreign'
    )

    post "/api/v1/accounts/#{account.id}/crm_activities",
         params: {
           crm_activity: {
             deal_id: foreign_deal.id,
             title: 'Invalid',
             activity_type: 'task'
           }
         },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
