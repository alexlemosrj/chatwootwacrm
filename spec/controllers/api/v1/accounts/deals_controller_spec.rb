require 'rails_helper'

RSpec.describe 'Deals API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:stage) { pipeline.pipeline_stages.first }

  describe 'POST /api/v1/accounts/:account_id/deals' do
    it 'creates an opportunity scoped to the account' do
      contact = create(:contact, account: account)

      expect do
        post "/api/v1/accounts/#{account.id}/deals",
             params: {
               deal: {
                 title: 'Plano Premium',
                 pipeline_id: pipeline.id,
                 pipeline_stage_id: stage.id,
                 contact_id: contact.id,
                 value: 2500,
                 currency: 'BRL'
               }
             },
             headers: agent.create_new_auth_token,
             as: :json
      end.to change(account.deals, :count).by(1)

      expect(response).to have_http_status(:success), response.body
      deal = account.deals.last
      expect(deal.contact_id).to eq(contact.id)
      expect(account.crm_events.where(deal: deal, event_type: 'deal_created')).to exist
    end

    it 'rejects a contact from another account' do
      foreign_contact = create(:contact, account: create(:account))

      post "/api/v1/accounts/#{account.id}/deals",
           params: {
             deal: {
               title: 'Cross account',
               pipeline_id: pipeline.id,
               pipeline_stage_id: stage.id,
               contact_id: foreign_contact.id
             }
           },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(account.deals.where(title: 'Cross account')).not_to exist
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/deals/:id' do
    it 'records stage and status transitions in the CRM timeline' do
      next_stage = pipeline.pipeline_stages.second
      deal = account.deals.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        title: 'Oportunidade'
      )

      patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
            params: {
              deal: {
                pipeline_stage_id: next_stage.id,
                status: 'won'
              }
            },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success), response.body
      expect(deal.reload.pipeline_stage_id).to eq(next_stage.id)
      expect(deal.status).to eq('won')
      expect(account.crm_events.where(deal: deal, event_type: 'stage_changed')).to exist
      expect(account.crm_events.where(deal: deal, event_type: 'status_changed')).to exist
    end
  end

  describe 'stage semantics' do
    it 'marks an opportunity as won when moved to a won stage' do
      won_stage = pipeline.pipeline_stages.find_by!(is_won: true)
      deal = account.deals.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        title: 'Fechamento'
      )

      patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
            params: { deal: { pipeline_stage_id: won_stage.id } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success), response.body
      expect(deal.reload.status).to eq('won')
      expect(deal.probability).to eq(won_stage.default_probability)
    end

    it 'marks an opportunity as lost when moved to a lost stage' do
      lost_stage = pipeline.pipeline_stages.create!(
        name: 'Perdido',
        position: 5,
        default_probability: 0,
        is_lost: true
      )
      deal = account.deals.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        title: 'Sem avanço'
      )

      patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
            params: { deal: { pipeline_stage_id: lost_stage.id } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success), response.body
      expect(deal.reload.status).to eq('lost')
      expect(deal.probability).to eq(0)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/deals/:id' do
    it 'preserves a deletion event after removing the opportunity' do
      deal = account.deals.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        title: 'Remover oportunidade'
      )

      delete "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:success), response.body
      expect(Deal.exists?(deal.id)).to be(false)

      event = account.crm_events.find_by!(event_type: 'deal_deleted')
      expect(event.deal_id).to be_nil
      expect(event.metadata.dig('from', 'title')).to eq('Remover oportunidade')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/deals' do
    it 'never returns deals from another account' do
      own_deal = account.deals.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        title: 'Minha oportunidade'
      )

      other_account = create(:account)
      other_pipeline = other_account.pipelines.find_by!(is_default: true)
      other_account.deals.create!(
        pipeline: other_pipeline,
        pipeline_stage: other_pipeline.pipeline_stages.first,
        title: 'Outra conta'
      )

      get "/api/v1/accounts/#{account.id}/deals",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success), response.body
      ids = response.parsed_body['payload'].map { |item| item['id'] }
      expect(ids).to contain_exactly(own_deal.id)
    end
  end
end
