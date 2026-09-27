class Crm::AutoLeadListener < BaseListener
  def message_created(event)
    message = event.data.fetch(:message)
    return unless message.incoming? && !message.private?
    return unless message.conversation.crm_auto_lead_eligible?

    Crm::AutoLeadJob.perform_later(message.account_id, message.conversation_id, message.id)
  end
end
