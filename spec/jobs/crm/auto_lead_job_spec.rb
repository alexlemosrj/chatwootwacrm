require 'rails_helper'

RSpec.describe Crm::AutoLeadJob do
  let(:account) { create(:account, settings: { crm_auto_lead_enabled: true }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, sender: conversation.contact) }

  it 'processes duplicate message.created events through the real dispatcher asynchronously' do
    create(:message, conversation: conversation, account: account, sender: conversation.contact, created_at: 3.minutes.ago)
    create(:message, conversation: conversation, account: account, message_type: :outgoing, status: :delivered, created_at: 2.minutes.ago)
    incoming = message
    clear_enqueued_jobs
    2.times { Rails.configuration.dispatcher.async_dispatcher.publish_event('message.created', Time.current, message: incoming) }
    expect(account.deals).to be_empty
    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(2)
    perform_enqueued_jobs(only: described_class)
    expect(account.deals.count).to eq(1)
  end

  it 'rejects a conversation belonging to another account' do
    other = create(:account)
    expect { described_class.perform_now(other.id, conversation.id, message.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Deal.count).to eq(0)
  end

  it 'rejects a message outside the conversation' do
    other_message = create(:message)
    expect { described_class.perform_now(account.id, conversation.id, other_message.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not dispatch CRM work for default factories' do
    ordinary = create(:message)
    event = Events::Base.new('message.created', Time.current, message: ordinary)
    expect { Crm::AutoLeadListener.instance.message_created(event) }.not_to have_enqueued_job(described_class)
  end

  it 'does not receive historical import creation events' do
    attributes = conversation.attributes.slice(*Conversation.column_names).except('id', 'display_id', 'uuid', 'crm_auto_lead_state')
    attributes['identifier'] = SecureRandom.uuid
    expect do
      row = Conversation.insert_all!([attributes], returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
      imported = account.conversations.find(row.rows.first.first)
      expect(imported).to be_crm_auto_lead_ineligible
    end.not_to have_enqueued_job(described_class)
  end

  it 'keeps the incoming message persisted when subsequent CRM processing fails' do
    create(:message, conversation: conversation, account: account, sender: conversation.contact, created_at: 3.minutes.ago)
    create(:message, conversation: conversation, account: account, message_type: :outgoing, status: :delivered, created_at: 2.minutes.ago)
    incoming = message
    account.pipelines.destroy_all
    expect { described_class.perform_now(account.id, conversation.id, incoming.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Message.exists?(incoming.id)).to be(true)
    expect(conversation.reload).to be_crm_auto_lead_eligible
  end
end
