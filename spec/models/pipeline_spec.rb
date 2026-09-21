require 'rails_helper'

RSpec.describe Pipeline do
  it 'belongs to an account and owns ordered stages' do
    account = create(:account)
    pipeline = account.pipelines.find_by!(is_default: true)

    expect(pipeline.account).to eq(account)
    expect(pipeline.pipeline_stages.pluck(:position)).to eq([0, 1, 2, 3, 4])
  end

  it 'does not allow destroying a pipeline that still has deals' do
    account = create(:account)
    pipeline = account.pipelines.find_by!(is_default: true)

    Deal.create!(
      account: account,
      pipeline: pipeline,
      pipeline_stage: pipeline.pipeline_stages.first,
      title: 'Negócio ativo'
    )

    expect(pipeline.destroy).to be(false)
    expect(pipeline.errors[:deals]).to be_present
  end
end
