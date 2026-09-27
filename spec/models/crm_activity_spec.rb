require 'rails_helper'

RSpec.describe CrmActivity do
  let(:account) { create(:account) }

  it 'accepts a deal and contact from the same account' do
    pipeline = account.pipelines.find_by!(is_default: true)
    contact = create(:contact, account: account)
    deal = Deal.create!(
      account: account,
      pipeline: pipeline,
      pipeline_stage: pipeline.pipeline_stages.first,
      contact: contact,
      title: 'Oportunidade'
    )

    activity = described_class.new(
      account: account,
      deal: deal,
      contact: contact,
      title: 'Retornar contato',
      activity_type: 'followup'
    )

    expect(activity).to be_valid
  end

  it 'rejects a deal from another account' do
    other_account = create(:account)
    other_pipeline = other_account.pipelines.find_by!(is_default: true)
    other_deal = Deal.create!(
      account: other_account,
      pipeline: other_pipeline,
      pipeline_stage: other_pipeline.pipeline_stages.first,
      title: 'Outra conta'
    )

    activity = described_class.new(
      account: account,
      deal: other_deal,
      title: 'Atividade inválida',
      activity_type: 'task'
    )

    expect(activity).not_to be_valid
    expect(activity.errors[:deal]).to include('must belong to the same account')
  end

  it 'rejects invalid activity types' do
    activity = described_class.new(
      account: account,
      title: 'Tipo inválido',
      activity_type: 'other'
    )

    expect(activity).not_to be_valid
  end
end
