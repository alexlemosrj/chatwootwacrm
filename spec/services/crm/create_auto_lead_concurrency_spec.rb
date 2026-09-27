require 'rails_helper'
require 'timeout'

RSpec.describe Crm::CreateAutoLead do
  self.use_transactional_tests = false

  let(:account) { create(:account, settings: { crm_auto_lead_enabled: true }) }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:message) do
    create(:message, conversation: conversation, account: account, sender: conversation.contact)
  end

  before do
    create(:message, conversation: conversation, account: account, sender: conversation.contact, created_at: 3.minutes.ago)
    create(:message, conversation: conversation, account: account, message_type: :outgoing, status: :delivered, created_at: 2.minutes.ago)
    message
  end

  after do
    # These fixtures commit on independent connections; remove only their rows, without async callbacks.
    user_ids = account.users.ids
    ContactInbox.where(inbox_id: account.inboxes.select(:id)).delete_all
    [CrmEvent, Deal, Message, Conversation, Contact, Inbox, Channel::WebWidget, AccountUser, WorkingHour, NotificationSetting].each do |model|
      model.where(account_id: account.id).delete_all
    end
    User.where(id: user_ids).delete_all
    account.delete
  end

  it 'serializes two independent database connections processing the same inbound' do
    ready = Queue.new
    release = Queue.new
    ids = [account.id, conversation.id, message.id]
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          Crm::AutoLeadJob.perform_now(*ids)
        end
      end
    end
    begin
      Timeout.timeout(10) do
        2.times { ready.pop }
        2.times { release << true }
        workers.each(&:value)
      end
      expect(account.deals.count).to eq(1)
      expect(account.crm_events.where(event_type: 'deal_created').count).to eq(1)
      expect(conversation.reload).to be_crm_auto_lead_processed
    ensure
      workers.each { |worker| worker.kill if worker.alive? }
      workers.each(&:join)
    end
  end

  it 'waits for an in-flight manual deal before consuming the journey' do
    saved = Queue.new
    release = Queue.new
    ids = [account.id, conversation.id, message.id]
    manual = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Deal.transaction do
          pipeline = account.pipelines.find_by!(is_default: true)
          account.deals.create!(title: 'Manual', conversation_id: ids[1], pipeline: pipeline, pipeline_stage: pipeline.pipeline_stages.first)
          saved << true
          release.pop
        end
      end
    end
    automatic = nil
    begin
      Timeout.timeout(10) do
        saved.pop
        automatic = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { Crm::AutoLeadJob.perform_now(*ids) }
        end
        release << true
        manual.value
        automatic.value
      end
      expect(account.deals.sole.title).to eq('Manual')
      expect(account.crm_events).to be_empty
      expect(conversation.reload).to be_crm_auto_lead_processed
    ensure
      [manual, automatic].compact.each { |worker| worker.kill if worker.alive? }
      [manual, automatic].compact.each(&:join)
    end
  end
end
