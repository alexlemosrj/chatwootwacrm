require 'rails_helper'

RSpec.describe Crm::CreateAutoLead do
  let(:account) { create(:account, settings: { crm_auto_lead_enabled: true }) }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:contact) { conversation.contact }
  let(:start_at) { 1.hour.ago }
  let(:first_message) do
    create(:message, conversation: conversation, account: account, sender: contact, created_at: start_at)
  end
  let(:reply_attributes) { { message_type: :outgoing, private: false, status: :delivered } }
  let(:reply) do
    create(:message, **reply_attributes, conversation: conversation, account: account, created_at: start_at + 1.minute)
  end
  let(:last_message) do
    create(:message, conversation: conversation, account: account, sender: contact, created_at: start_at + 2.minutes)
  end
  let(:service) { described_class.new(conversation: conversation, message: last_message) }

  it 'ignores a single inbound' do
    expect { described_class.new(conversation: conversation, message: first_message).perform }.not_to change(Deal, :count)
  end

  it 'ignores inbound followed by inbound' do
    first_message
    expect { service.perform }.not_to change(Deal, :count)
  end

  it 'does not convert on the outgoing response' do
    first_message
    expect { described_class.new(conversation: conversation, message: reply).perform }.not_to change(Deal, :count)
  end

  it 'ignores outbound followed by inbound without the initial inbound' do
    reply
    expect { service.perform }.not_to change(Deal, :count)
  end

  context 'with an inbound, a public outgoing response and a later inbound' do
    before do
      first_message
      reply
      last_message
    end

    it 'creates one opportunity and an automatic audit event atomically' do
      expect { service.perform }.to change(Deal, :count).by(1).and change(CrmEvent, :count).by(1)
      deal = account.deals.sole
      pipeline = account.pipelines.find_by!(is_default: true)
      expect(deal).to have_attributes(conversation_id: conversation.id, contact_id: contact.id,
                                      pipeline_id: pipeline.id, pipeline_stage_id: pipeline.pipeline_stages.first.id)
      expect(deal.crm_events.sole.metadata).to include('source' => 'auto_lead', 'conversation_id' => conversation.id,
                                                       'message_id' => last_message.id)
      expect(conversation.reload).to be_crm_auto_lead_processed
    end

    it 'does not duplicate on retry or subsequent inbound messages' do
      service.perform
      another = create(:message, conversation: conversation, account: account, sender: contact, created_at: start_at + 3.minutes)
      expect do
        service.perform
        described_class.new(conversation: conversation, message: another).perform
      end.not_to change(Deal, :count)
    end

    it 'does not convert when the first inbound event is processed after later messages' do
      expect { described_class.new(conversation: conversation, message: first_message).perform }.not_to change(Deal, :count)
      expect { service.perform }.to change(Deal, :count).by(1)
    end

    it 'cannot retroactively convert a conversation born before activation' do
      conversation.update!(crm_auto_lead_state: :ineligible)
      expect { service.perform }.not_to change(Deal, :count)
    end

    it 'requires the initial inbound to be a valid customer interaction too' do
      first_message.update!(private: true)
      expect { service.perform }.not_to change(Deal, :count)
    end

    it 'uses the real PK despite a display id colliding with another conversation PK' do
      other = create(:conversation, account: account)
      conversation.update!(display_id: other.id)
      expect(conversation.id).not_to eq(conversation.display_id)
      service.perform
      expect(account.deals.sole.conversation_id).to eq(conversation.id)
    end

    it 'does not mix accounts with identical display ids' do
      other = create(:conversation)
      other.update!(display_id: conversation.display_id)
      service.perform
      expect(other.account.deals).to be_empty
      expect(account.deals.sole.conversation_id).to eq(conversation.id)
    end

    it 'consumes an existing manual deal without changing its audit or creating another' do
      pipeline = account.pipelines.find_by!(is_default: true)
      manual = account.deals.create!(title: 'Manual', conversation: conversation, pipeline: pipeline,
                                     pipeline_stage: pipeline.pipeline_stages.first)
      expect { service.perform }.not_to change(Deal, :count)
      expect(manual.crm_events).to be_empty
      expect(conversation.reload).to be_crm_auto_lead_processed
      manual.destroy!
      expect { service.perform }.not_to change(Deal, :count)
    end

    %w[destroy unlink move won lost].each do |change|
      it "never recreates after #{change} of the generated deal" do
        service.perform
        deal = account.deals.sole
        case change
        when 'destroy' then deal.destroy!
        when 'unlink' then deal.update!(conversation: nil)
        when 'move' then deal.update!(pipeline_stage: deal.pipeline.pipeline_stages.second)
        else deal.update!(status: change)
        end
        expect { service.perform }.not_to change(Deal, :count)
      end
    end

    it 'does not convert after resolution and reopening' do
      conversation.resolved!
      conversation.open!
      expect { service.perform }.not_to change(Deal, :count)
      expect(conversation.reload).to be_crm_auto_lead_closed
    end

    it 'allows a long-running open journey without an arbitrary time window' do
      conversation.update!(created_at: 1.year.ago)
      expect { service.perform }.to change(Deal, :count).by(1)
    end

    it 'uses the default pipeline and position ordering rather than stage names or IDs' do
      original = account.pipelines.find_by!(is_default: true)
      original.update!(is_default: false)
      pipeline = account.pipelines.create!(name: 'Custom', is_default: true)
      pipeline.pipeline_stages.create!(name: 'Later', position: 4)
      first = pipeline.pipeline_stages.create!(name: 'Renamed entry', position: 2, default_probability: 42)
      service.perform
      expect(account.deals.sole).to have_attributes(pipeline_id: pipeline.id, pipeline_stage_id: first.id, probability: 42)
    end

    it 'leaves the journey eligible when the default pipeline is missing' do
      account.pipelines.destroy_all
      expect { service.perform }.to raise_error(ActiveRecord::RecordNotFound)
      expect(account.deals).to be_empty
      expect(conversation.reload).to be_crm_auto_lead_eligible
    end

    it 'leaves the journey eligible when its pipeline has no stages' do
      account.pipelines.first.pipeline_stages.destroy_all
      expect { service.perform }.to raise_error(ActiveRecord::RecordNotFound)
      expect(conversation.reload).to be_crm_auto_lead_eligible
    end

    it 'rolls back deal and state on audit failure and permits retry' do
      allow(CrmEvent).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
      expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
      expect(account.deals).to be_empty
      expect(account.crm_events).to be_empty
      expect(conversation.reload).to be_crm_auto_lead_eligible
      allow(CrmEvent).to receive(:new).and_call_original
      expect { service.perform }.to change(Deal, :count).by(1)
    end

    it 'does not consume the journey on deal failure' do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with('crm.auto_lead_title', name: contact.name).and_return(nil)
      expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
      expect(account.crm_events).to be_empty
      expect(conversation.reload).to be_crm_auto_lead_eligible
    end

    it 'does not create with a contact from another account' do
      allow(conversation).to receive(:contact).and_return(create(:contact))
      expect { service.perform }.not_to change(Deal, :count)
    end

    it 'does not create without a contact' do
      allow(conversation).to receive(:contact).and_return(nil)
      expect { service.perform }.not_to change(Deal, :count)
    end

    it 'pauses processing when disabled without retroactively enabling other conversations' do
      account.update!(crm_auto_lead_enabled: false)
      ineligible = create(:conversation, account: account)
      expect { service.perform }.not_to change(Deal, :count)
      account.update!(crm_auto_lead_enabled: true)
      expect(ineligible.reload).to be_crm_auto_lead_ineligible
      expect { service.perform }.to change(Deal, :count).by(1)
    end

    [0, 2.minutes, 3.minutes].each do |offset|
      it "rejects a reply outside strict A < B < C (offset #{offset})" do
        reply.update!(created_at: start_at + offset)
        expect { service.perform }.not_to change(Deal, :count)
      end
    end

    [:private, :activity, :voice_call, :deleted, :failed, :auto_reply].each do |kind|
      it "rejects #{kind} incoming C" do
        case kind
        when :private then last_message.update!(private: true)
        when :activity then last_message.update!(message_type: :activity)
        when :voice_call then last_message.update!(content_type: :voice_call)
        when :deleted then last_message.update!(deleted: true)
        when :failed then last_message.update!(status: :failed)
        when :auto_reply then last_message.update!(content_type: :incoming_email, content_attributes: { email: { auto_reply: true } })
        end
        expect { service.perform }.not_to change(Deal, :count)
      end
    end
  end

  {
    private: { message_type: :outgoing, private: true, status: :delivered },
    activity: { message_type: :activity, status: :delivered },
    # Greeting and away messages are templates: deliberately excluded in v1, even if delivered.
    greeting_template: { message_type: :template, content: 'Hello', status: :delivered },
    away_template: { message_type: :template, content: 'We are away', status: :delivered },
    voice_call: { message_type: :outgoing, content_type: :voice_call, status: :delivered },
    deleted: { message_type: :outgoing, content_attributes: { deleted: true }, status: :delivered },
    failed: { message_type: :outgoing, status: :failed, source_id: 'provider-id' },
    pending_send: { message_type: :outgoing, status: :sent, source_id: nil },
    empty_reply: { message_type: :outgoing, status: :delivered, content: ' ' }
  }.each do |kind, attributes|
    context "with #{kind} instead of a business response" do
      let(:reply_attributes) { attributes }

      it 'does not convert' do
        first_message
        reply
        expect { service.perform }.not_to change(Deal, :count)
      end
    end
  end

  it 'accepts a delivered public attachment without text as the business response' do
    first_message
    create(:message, :with_attachment, conversation: conversation, account: account, message_type: :outgoing,
                                       status: :delivered, content: nil, created_at: start_at + 1.minute)
    expect { service.perform }.to change(Deal, :count).by(1)
  end

  [:human, :automation, :bot, :ai, :provider_ack].each do |origin|
    it "accepts a valid outgoing from #{origin}" do
      first_message
      response = reply
      case origin
      when :automation then response.update!(sender: nil, content_attributes: { automation_rule_id: 1 })
      when :bot then response.update!(sender: create(:agent_bot, account: account))
      # Polymorphic Captain sender is deliberately not required by the OSS service.
      when :ai
        # Exercise the polymorphic sender without loading Enterprise in the OSS suite.
        response.update_columns(sender_type: 'Captain::Assistant', sender_id: 123) # rubocop:disable Rails/SkipsModelValidations
      when :provider_ack then response.update!(status: :sent, source_id: 'provider-id', sender: nil)
      end
      expect { service.perform }.to change(Deal, :count).by(1)
    end
  end
end
