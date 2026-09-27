# frozen_string_literal: true

class HardenCrmLifecycleReferences < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_events, :actor_snapshot, :jsonb, null: false, default: {}
    execute <<~SQL.squish
      UPDATE crm_events
      SET actor_snapshot = jsonb_build_object('id', users.id, 'name', users.name)
      FROM users WHERE users.id = crm_events.actor_id
    SQL

    change_reference(:deals, :conversations, :conversation_id, :nullify)
    change_reference(:deals, :users, :assignee_id, :nullify)
    change_reference(:crm_activities, :users, :assignee_id, :nullify)
    change_reference(:crm_events, :users, :actor_id, :nullify)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Actor snapshots preserve historical authorship and must not be removed'
  end

  private

  def change_reference(table, target, column, on_delete)
    remove_foreign_key table, column: column
    add_foreign_key table, target, column: column, on_delete: on_delete
  end
end
