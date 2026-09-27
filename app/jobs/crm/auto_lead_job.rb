class Crm::AutoLeadJob < ApplicationJob
  queue_as :default

  def perform(account_id, conversation_id, message_id)
    account = Account.find(account_id)
    conversation = account.conversations.find(conversation_id)
    message = conversation.messages.find_by!(id: message_id, account_id: account.id)
    Crm::CreateAutoLead.new(conversation: conversation, message: message).perform
  end
end
