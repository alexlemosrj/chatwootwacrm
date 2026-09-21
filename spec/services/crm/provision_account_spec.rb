require 'rails_helper'

RSpec.describe Crm::ProvisionAccount do
  describe '.call' do
    it 'creates one default pipeline with default stages for a new account' do
      account = create(:account)

      pipeline = account.pipelines.find_by(is_default: true)

      expect(pipeline).to be_present
      expect(account.pipelines.count).to eq(1)
      expect(pipeline.pipeline_stages.order(:position).pluck(:name)).to eq(
        ['Novo Lead', 'Qualificado', 'Proposta', 'Negociação', 'Ganho']
      )
    end

    it 'is idempotent' do
      account = create(:account)

      2.times { described_class.call(account) }

      expect(account.pipelines.count).to eq(1)
      expect(account.pipelines.find_by(is_default: true).pipeline_stages.count).to eq(5)
    end

    it 'keeps accounts isolated' do
      first_account = create(:account)
      second_account = create(:account)

      first_pipeline = described_class.call(first_account)
      second_pipeline = described_class.call(second_account)

      expect(first_pipeline.account_id).to eq(first_account.id)
      expect(second_pipeline.account_id).to eq(second_account.id)
      expect(first_pipeline.id).not_to eq(second_pipeline.id)
    end
  end
end
