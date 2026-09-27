require 'rails_helper'

RSpec.describe Deal do
  let(:account) { create(:account) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:stage) { pipeline.pipeline_stages.first }

  it 'accepts references that belong to the same account and pipeline' do
    contact = create(:contact, account: account)
    deal = described_class.new(
      account: account,
      pipeline: pipeline,
      pipeline_stage: stage,
      contact: contact,
      title: 'Nova oportunidade'
    )

    expect(deal).to be_valid
  end

  it 'rejects a pipeline from another account' do
    other_pipeline = create(:account).pipelines.find_by!(is_default: true)
    deal = described_class.new(
      account: account,
      pipeline: other_pipeline,
      pipeline_stage: other_pipeline.pipeline_stages.first,
      title: 'Cross account'
    )

    expect(deal).not_to be_valid
    expect(deal.errors[:pipeline]).to include('must belong to the same account')
  end

  it 'rejects a stage from another pipeline' do
    second_pipeline = account.pipelines.create!(name: 'Segundo funil')
    second_stage = second_pipeline.pipeline_stages.create!(name: 'Entrada', position: 0)
    deal = described_class.new(
      account: account,
      pipeline: pipeline,
      pipeline_stage: second_stage,
      title: 'Stage mismatch'
    )

    expect(deal).not_to be_valid
    expect(deal.errors[:pipeline_stage]).to include('must belong to the selected pipeline')
  end

  it 'rejects a contact from another account' do
    other_contact = create(:contact, account: create(:account))
    deal = described_class.new(
      account: account,
      pipeline: pipeline,
      pipeline_stage: stage,
      contact: other_contact,
      title: 'Cross account contact'
    )

    expect(deal).not_to be_valid
    expect(deal.errors[:contact]).to include('must belong to the same account')
  end

  it 'rejects an assignee who is not a member of the account' do
    outsider = create(:user)
    deal = described_class.new(
      account: account,
      pipeline: pipeline,
      pipeline_stage: stage,
      assignee: outsider,
      title: 'Invalid assignee'
    )

    expect(deal).not_to be_valid
    expect(deal.errors[:assignee]).to include('must belong to the same account')
  end
end
