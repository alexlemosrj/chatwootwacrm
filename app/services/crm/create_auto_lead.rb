class Crm::CreateAutoLead
  pattr_initialize [:conversation!, :message!]

  def perform
    conversation.with_lock do
      return unless eligible_journey? && qualifying_sequence?

      create_deal! unless conversation.deals.exists?
      conversation.update!(crm_auto_lead_state: :processed)
    end
  end

  private

  delegate :account, :contact, to: :conversation

  def eligible_journey?
    conversation.crm_auto_lead_eligible? && account.reload.crm_auto_lead_enabled == true &&
      contact.present? && contact.account_id == account.id
  end

  def interaction_messages
    conversation.messages.where(account_id: account.id, private: false)
                .where.not(content_type: [:voice_call, :input_csat, :input_email, :form])
                .where.not(status: :failed)
                .where(<<~SQL.squish)
                  NULLIF(BTRIM(messages.content), '') IS NOT NULL OR
                  EXISTS (SELECT 1 FROM attachments WHERE attachments.message_id = messages.id)
                SQL
                .where("COALESCE((content_attributes #>> '{}')::jsonb ->> 'deleted', 'false') != 'true'")
                .where("COALESCE((content_attributes #>> '{}')::jsonb -> 'email' ->> 'auto_reply', 'false') != 'true'")
  end

  def incoming_messages
    interaction_messages.incoming.where(sender: contact)
  end

  def qualifying_sequence?
    return false unless incoming_messages.exists?(id: message.id)

    first_incoming_at = incoming_messages.where('created_at < ?', message.created_at).minimum(:created_at)
    return false unless first_incoming_at

    replies = interaction_messages.outgoing.where('created_at > ? AND created_at < ?', first_incoming_at, message.created_at)
    # `sent` is the initial state, not proof of sending. A provider ID or receipt is required.
    replies.where(status: [:delivered, :read])
           .or(replies.where(status: :sent).where.not(source_id: [nil, ''])).exists?
  end

  def stage_status(stage)
    return 'won' if stage.is_won?
    return 'lost' if stage.is_lost?

    'open'
  end

  def create_deal!
    pipeline = account.pipelines.find_by!(is_default: true)
    stage = pipeline.pipeline_stages.first!
    deal = account.deals.create!(
      crm_creation_source: :auto_lead, conversation: conversation, contact: contact, pipeline: pipeline, pipeline_stage: stage,
      title: I18n.t('crm.auto_lead_title', name: contact.name),
      probability: stage.default_probability, status: stage_status(stage)
    )
    account.crm_events.create!(
      deal: deal, contact: contact, event_type: 'deal_created',
      metadata: { source: 'auto_lead', conversation_id: conversation.id, message_id: message.id }
    )
  end
end
