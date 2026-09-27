require 'rails_helper'

RSpec.describe Crm::AutoLeadJourney do
  let(:account) { create(:account) }

  it 'keeps ordinary factories and old conversations ineligible after activation' do
    old = create(:conversation, account: account)
    expect(old).to be_crm_auto_lead_ineligible
    account.update!(crm_auto_lead_enabled: true)
    expect(old.reload).to be_crm_auto_lead_ineligible
    expect(create(:conversation, account: account)).to be_crm_auto_lead_eligible
    expect(account.deals).to be_empty
  end

  it 'reads activation from persisted settings even with a stale account instance' do
    stale = Account.find(account.id)
    account.update!(crm_auto_lead_enabled: true)
    expect(create(:conversation, account: stale)).to be_crm_auto_lead_eligible
  end

  it 'does not rearm journeys across disable and reenable' do
    account.update!(crm_auto_lead_enabled: true)
    eligible = create(:conversation, account: account)
    account.update!(crm_auto_lead_enabled: false)
    disabled = create(:conversation, account: account)
    account.update!(crm_auto_lead_enabled: true)
    expect(disabled.reload).to be_crm_auto_lead_ineligible
    expect(eligible.reload).to be_crm_auto_lead_eligible
  end

  it 'closes permanently upon resolution, including processed journeys' do
    account.update!(crm_auto_lead_enabled: true)
    [:eligible, :processed].each do |state|
      conversation = create(:conversation, account: account)
      conversation.update!(crm_auto_lead_state: state)
      conversation.resolved!
      conversation.open!
      expect(conversation.reload).to be_crm_auto_lead_closed
    end
  end

  it 'does not arm a conversation created resolved' do
    account.update!(crm_auto_lead_enabled: true)
    conversation = create(:conversation, account: account, status: :resolved)
    conversation.open!
    expect(conversation.reload).to be_crm_auto_lead_closed
  end

  it 'rejects a non-boolean activation setting' do
    account.crm_auto_lead_enabled = 'true'
    expect(account).not_to be_valid
  end

  it 'does not lock or discard unsaved changes on the callers account instance' do
    account.update!(crm_auto_lead_enabled: true)
    account.name = 'Unsaved local edit'
    expect(create(:conversation, account: account)).to be_crm_auto_lead_eligible
    expect(account.name).to eq('Unsaved local edit')
    expect(Account.find(account.id).name).not_to eq('Unsaved local edit')
  end
end
