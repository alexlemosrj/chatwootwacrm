class AddCrmAutoLeadStateToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :crm_auto_lead_state, :integer, null: false, default: 0
    add_check_constraint :conversations, 'crm_auto_lead_state IN (0, 1, 2, 3)', name: 'conversations_crm_auto_lead_state_values'
  end
end
