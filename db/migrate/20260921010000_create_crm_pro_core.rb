class CreateCrmProCore < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.timestamps
    end
    add_index :pipelines, [:account_id, :name]
    add_index :pipelines, :account_id, unique: true, where: 'is_default = TRUE', name: 'index_pipelines_one_default_per_account'

    create_table :pipeline_stages do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.string :color, null: false, default: '#3b82f6'
      t.decimal :default_probability, precision: 5, scale: 2, null: false, default: 0
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.timestamps
    end
    add_index :pipeline_stages, [:pipeline_id, :position]
    add_check_constraint :pipeline_stages,
                         'default_probability >= 0 AND default_probability <= 100',
                         name: 'pipeline_stages_probability_range'
    add_check_constraint :pipeline_stages,
                         'NOT (is_won AND is_lost)',
                         name: 'pipeline_stages_not_won_and_lost'

    create_table :deals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: true
      t.references :pipeline_stage, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.decimal :value, precision: 14, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: 'BRL'
      t.decimal :expected_revenue, precision: 14, scale: 2, null: false, default: 0
      t.decimal :probability, precision: 5, scale: 2, null: false, default: 0
      t.integer :priority_stars, null: false, default: 0
      t.date :expected_close_date
      t.string :status, null: false, default: 'open'
      t.text :notes
      t.string :campaign_source
      t.jsonb :utm_data, null: false, default: {}
      t.jsonb :custom_attributes, null: false, default: {}
      t.timestamps
    end
    add_index :deals, [:account_id, :pipeline_id]
    add_index :deals, [:account_id, :status]
    add_index :deals, [:account_id, :assignee_id]
    add_index :deals, [:pipeline_stage_id, :status]
    add_check_constraint :deals, "status IN ('open', 'won', 'lost')", name: 'deals_status_values'
    add_check_constraint :deals, 'probability >= 0 AND probability <= 100', name: 'deals_probability_range'
    add_check_constraint :deals, 'priority_stars >= 0 AND priority_stars <= 3', name: 'deals_priority_stars_range'

    create_table :crm_activities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :deal, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :activity_type, null: false
      t.string :title, null: false
      t.datetime :start_at
      t.datetime :due_at
      t.datetime :completed_at
      t.string :status, null: false, default: 'planned'
      t.text :notes
      t.timestamps
    end
    add_index :crm_activities, [:account_id, :status, :due_at]
    add_index :crm_activities, [:deal_id, :status]
    add_check_constraint :crm_activities,
                         "activity_type IN ('call', 'whatsapp', 'meeting', 'followup', 'task', 'email')",
                         name: 'crm_activities_type_values'
    add_check_constraint :crm_activities,
                         "status IN ('planned', 'completed', 'cancelled')",
                         name: 'crm_activities_status_values'

    create_table :crm_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :deal, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :crm_events, [:account_id, :created_at]
    add_index :crm_events, [:deal_id, :created_at]
  end
end
