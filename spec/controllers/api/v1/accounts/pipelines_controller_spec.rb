require 'rails_helper'

RSpec.describe 'Pipelines API', type: :request do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/pipelines' do
    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/pipelines"
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when authenticated as agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'seeds default pipeline and lists it' do
        get "/api/v1/accounts/#{account.id}/pipelines",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['payload'].length).to eq(1)
        expect(body['payload'].first['name']).to eq('Sales Pipeline')
        expect(body['payload'].first['stages'].length).to eq(5)
      end

      it 'does not leak other account pipelines' do
        create(:pipeline, account: other_account, name: 'Secret')
        get "/api/v1/accounts/#{account.id}/pipelines",
            headers: agent.create_new_auth_token,
            as: :json

        names = response.parsed_body['payload'].pluck('name')
        expect(names).not_to include('Secret')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/pipelines' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'allows admin to create pipeline with default stages' do
      post "/api/v1/accounts/#{account.id}/pipelines",
           params: { pipeline: { name: 'Outbound' } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].length).to eq(5)
    end

    it 'forbids agent from creating pipeline' do
      post "/api/v1/accounts/#{account.id}/pipelines",
           params: { pipeline: { name: 'Outbound' } },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

RSpec.describe 'Deals API', type: :request do
  let!(:account) { create(:account) }
  let!(:pipeline) { create(:pipeline, account: account) }
  let!(:stage) { create(:pipeline_stage, pipeline: pipeline) }
  let!(:stage_two) { create(:pipeline_stage, pipeline: pipeline, position: 1) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/{account.id}/deals' do
    it 'creates a deal' do
      post "/api/v1/accounts/#{account.id}/deals",
           params: {
             deal: {
               title: 'Acme deal',
               pipeline_id: pipeline.id,
               pipeline_stage_id: stage.id,
               value: 2500,
               currency: 'BRL'
             }
           },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['title']).to eq('Acme deal')
      expect(response.parsed_body['value']).to eq(2500.0)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/deals/:id' do
    let!(:deal) { create(:deal, account: account, pipeline: pipeline, pipeline_stage: stage) }

    it 'moves deal to another stage' do
      patch "/api/v1/accounts/#{account.id}/deals/#{deal.id}",
            params: { deal: { pipeline_stage_id: stage_two.id } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.pipeline_stage_id).to eq(stage_two.id)
    end

    it 'does not allow updating deal from another account' do
      other = create(:account)
      other_pipeline = create(:pipeline, account: other)
      other_stage = create(:pipeline_stage, pipeline: other_pipeline)
      foreign = create(:deal, account: other, pipeline: other_pipeline, pipeline_stage: other_stage)

      patch "/api/v1/accounts/#{account.id}/deals/#{foreign.id}",
            params: { deal: { title: 'hacked' } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
