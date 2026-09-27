require 'rails_helper'

RSpec.describe Deal do
  let(:account) { create(:account, settings: { crm_auto_lead_enabled: true }) }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal) do
    account.deals.new(title: 'Manual', conversation: conversation, pipeline: pipeline, pipeline_stage: pipeline.pipeline_stages.first)
  end

  it 'consumes the eligible journey as soon as a manual deal is persisted' do
    deal.save!
    expect(conversation.reload).to be_crm_auto_lead_processed
    expect(account.deals.sole).to eq(deal)
    expect(account.crm_events).to be_empty
  end

  it 'consumes the journey when an existing manual deal is linked' do
    deal.conversation = nil
    deal.save!
    expect(conversation.reload).to be_crm_auto_lead_eligible
    deal.update!(conversation: conversation)
    expect(conversation.reload).to be_crm_auto_lead_processed
  end

  %w[destroy unlink move won lost].each do |change|
    it "does not automate after #{change} of a manual deal, even before the first qualifying sequence" do
      deal.save!
      case change
      when 'destroy' then deal.destroy!
      when 'unlink' then deal.update!(conversation: nil)
      when 'move' then deal.update!(pipeline_stage: pipeline.pipeline_stages.second)
      else deal.update!(status: change)
      end
      create(:message, conversation: conversation, account: account, sender: conversation.contact, created_at: 3.minutes.ago)
      create(:message, conversation: conversation, account: account, message_type: :outgoing, status: :delivered, created_at: 2.minutes.ago)
      incoming = create(:message, conversation: conversation, account: account, sender: conversation.contact)

      expect { Crm::AutoLeadJob.perform_now(account.id, conversation.id, incoming.id) }.not_to change(described_class, :count)
      expect(conversation.reload).to be_crm_auto_lead_processed
      expect(account.crm_events).to be_empty
    end
  end

  it 'does not consume on an invalid manual deal' do
    deal.title = nil
    expect { deal.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(deal).not_to be_persisted
    expect(deal.id).to be_nil
    expect(conversation.reload).to be_crm_auto_lead_eligible
    expect(account.deals.reload).to be_empty
  end

  it 'does not consume on cross-account references' do
    deal.conversation = create(:conversation)
    expect { deal.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(conversation.reload).to be_crm_auto_lead_eligible
    expect(deal.conversation.reload).to be_crm_auto_lead_ineligible
  end

  it 'rolls back consumption with the manual deal transaction' do
    deal
    described_class.transaction(requires_new: true) do
      deal.save!
      expect(conversation.reload).to be_crm_auto_lead_processed
      raise ActiveRecord::Rollback
    end
    expect(conversation.reload).to be_crm_auto_lead_eligible
    expect(account.deals.reload).to be_empty
  end

  it 'rolls back the persisted deal if consuming the journey fails' do
    allow(account).to receive(:conversations).and_return(Conversation.where(account_id: account.id))
    allow(account.conversations).to receive(:find).with(conversation.id).and_return(conversation)
    allow(conversation).to receive(:update!).with(crm_auto_lead_state: :processed).and_raise(ActiveRecord::RecordInvalid)
    expect { deal.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(conversation.reload).to be_crm_auto_lead_eligible
    expect(account.deals.reload).to be_empty
  end

  [:ineligible, :closed].each do |state|
    it "preserves a #{state} journey when saving a manual deal" do
      conversation.update!(crm_auto_lead_state: state)
      deal.save!
      expect(conversation.reload.crm_auto_lead_state).to eq(state.to_s)
    end
  end

  it 'preserves a processed journey when editing its deal' do
    deal.save!
    deal.update!(title: 'Edited', status: 'won')
    expect(conversation.reload).to be_crm_auto_lead_processed
  end

  it 'rejects a new link to a consumed journey even after the original deal is deleted' do
    deal.save!
    deal.destroy!
    replacement = deal.dup
    expect { replacement.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(conversation.reload).to be_crm_auto_lead_processed
    expect(account.deals.reload).to be_empty
  end
end
