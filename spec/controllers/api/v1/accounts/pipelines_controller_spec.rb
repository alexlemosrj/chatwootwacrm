require 'rails_helper'

RSpec.describe 'Pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }

  describe 'GET /api/v1/accounts/:account_id/pipelines' do
    it 'requires authentication' do
      get "/api/v1/accounts/#{account.id}/pipelines"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the provisioned pipeline and stages' do
      get "/api/v1/accounts/#{account.id}/pipelines",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.length).to eq(1)
      expect(payload.first['is_default']).to be(true)
      expect(payload.first['stages'].map { |stage| stage['name'] }).to eq(
        ['Novo Lead', 'Qualificado', 'Proposta', 'Negociação', 'Ganho']
      )
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pipelines' do
    it 'can create a blank pipeline' do
      expect do
        post "/api/v1/accounts/#{account.id}/pipelines",
             params: {
               pipeline: {
                 name: 'Enterprise',
                 with_default_stages: false
               }
             },
             headers: agent.create_new_auth_token,
             as: :json
      end.to change(account.pipelines, :count).by(1)

      expect(response).to have_http_status(:success)
      created = account.pipelines.find_by!(name: 'Enterprise')
      expect(created.pipeline_stages).to be_empty
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/pipelines/:pipeline_id/pipeline_stages/reorder' do
    it 'reorders only stages from the selected account pipeline' do
      first, second = pipeline.pipeline_stages.order(:position).first(2)

      patch "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/pipeline_stages/reorder",
            params: {
              stages: [
                { id: first.id, position: 1 },
                { id: second.id, position: 0 }
              ]
            },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it 'rejects a stage from another account' do
      other_account = create(:account)
      foreign_stage = other_account.pipelines.find_by!(is_default: true).pipeline_stages.first

      patch "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/pipeline_stages/reorder",
            params: {
              stages: [{ id: foreign_stage.id, position: 0 }]
            },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
