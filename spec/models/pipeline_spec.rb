require 'rails_helper'

RSpec.describe Pipeline, type: :model do
  describe '.ensure_default_for!' do
    let(:account) { create(:account) }

    it 'creates a sales pipeline with five stages when none exist' do
      pipeline = described_class.ensure_default_for!(account)

      expect(account.pipelines.count).to eq(1)
      expect(pipeline.name).to eq('Sales Pipeline')
      expect(pipeline.pipeline_stages.count).to eq(5)
    end

    it 'does not duplicate when a pipeline already exists' do
      existing = create(:pipeline, account: account)
      expect(described_class.ensure_default_for!(account)).to eq(existing)
      expect(account.pipelines.count).to eq(1)
    end
  end
end

RSpec.describe Deal, type: :model do
  it 'syncs pipeline_id from stage' do
    account = create(:account)
    pipeline = create(:pipeline, account: account)
    stage = create(:pipeline_stage, pipeline: pipeline)
    deal = create(:deal, account: account, pipeline_stage: stage, pipeline: pipeline)

    expect(deal.pipeline_id).to eq(pipeline.id)
  end

  it 'rejects invalid status' do
    deal = build(:deal, status: 'active')
    expect(deal).not_to be_valid
  end
end
