# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class CreateCrmProCore < ActiveRecord::Migration[7.1]
  def up
    ensure_pipelines
    ensure_pipeline_stages
    ensure_deals
    ensure_crm_activities
    ensure_crm_events
  end

  def down
    drop_table :crm_events, if_exists: true
    drop_table :crm_activities, if_exists: true

    remove_column :deals, :custom_attributes if column_exists?(:deals, :custom_attributes)
    remove_column :deals, :utm_data if column_exists?(:deals, :utm_data)
    remove_column :deals, :campaign_source if column_exists?(:deals, :campaign_source)
    remove_column :deals, :priority_stars if column_exists?(:deals, :priority_stars)
    remove_column :deals, :probability if column_exists?(:deals, :probability)
    remove_column :deals, :expected_revenue if column_exists?(:deals, :expected_revenue)

    remove_column :pipeline_stages, :is_lost if column_exists?(:pipeline_stages, :is_lost)
    remove_column :pipeline_stages, :is_won if column_exists?(:pipeline_stages, :is_won)
    remove_column :pipeline_stages, :default_probability if column_exists?(:pipeline_stages, :default_probability)
    remove_column :pipelines, :is_default if column_exists?(:pipelines, :is_default)
  end

  private

  def ensure_pipelines
    unless table_exists?(:pipelines)
      create_table :pipelines do |t|
        t.references :account, null: false, foreign_key: true
        t.string :name, null: false
        t.boolean :is_default, null: false, default: false
        t.timestamps
      end
    end

    add_column :pipelines, :is_default, :boolean, null: false, default: false unless column_exists?(:pipelines, :is_default)
    add_index :pipelines, [:account_id, :name] unless index_exists?(:pipelines, [:account_id, :name])
    return if index_exists?(:pipelines, :account_id, name: 'index_pipelines_one_default_per_account')

    add_index :pipelines,
              :account_id,
              unique: true,
              where: 'is_default = TRUE',
              name: 'index_pipelines_one_default_per_account'
  end

  def ensure_pipeline_stages
    unless table_exists?(:pipeline_stages)
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
    end

    add_column :pipeline_stages, :default_probability, :decimal, precision: 5, scale: 2, null: false, default: 0 unless column_exists?(:pipeline_stages, :default_probability)
    add_column :pipeline_stages, :is_won, :boolean, null: false, default: false unless column_exists?(:pipeline_stages, :is_won)
    add_column :pipeline_stages, :is_lost, :boolean, null: false, default: false unless column_exists?(:pipeline_stages, :is_lost)

    normalize_stage_positions
    remove_index :pipeline_stages, column: [:pipeline_id, :position] if index_exists?(:pipeline_stages, [:pipeline_id, :position]) &&
                                                                           !index_exists?(:pipeline_stages, [:pipeline_id, :position], unique: true)
    add_index :pipeline_stages, [:pipeline_id, :position], unique: true unless index_exists?(:pipeline_stages, [:pipeline_id, :position], unique: true)

    add_check_constraint :pipeline_stages,
                         'default_probability >= 0 AND default_probability <= 100',
                         name: 'pipeline_stages_probability_range' unless check_constraint_exists?(:pipeline_stages, name: 'pipeline_stages_probability_range')
    add_check_constraint :pipeline_stages,
                         'NOT (is_won AND is_lost)',
                         name: 'pipeline_stages_not_won_and_lost' unless check_constraint_exists?(:pipeline_stages, name: 'pipeline_stages_not_won_and_lost')
  end

  def normalize_stage_positions
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY pipeline_id ORDER BY position, id) - 1 AS normalized_position
        FROM pipeline_stages
      )
      UPDATE pipeline_stages
      SET position = ranked.normalized_position
      FROM ranked
      WHERE pipeline_stages.id = ranked.id
    SQL
  end

  def ensure_deals
    create_deals_table unless table_exists?(:deals)

    change_column :deals, :value, :decimal, precision: 14, scale: 2, null: false, default: 0
    change_column_default :deals, :currency, from: 'USD', to: 'BRL' if column_exists?(:deals, :currency)

    add_column :deals, :expected_revenue, :decimal, precision: 14, scale: 2, null: false, default: 0 unless column_exists?(:deals, :expected_revenue)
    add_column :deals, :probability, :decimal, precision: 5, scale: 2, null: false, default: 0 unless column_exists?(:deals, :probability)
    add_column :deals, :priority_stars, :integer, null: false, default: 0 unless column_exists?(:deals, :priority_stars)
    add_column :deals, :campaign_source, :string unless column_exists?(:deals, :campaign_source)
    add_column :deals, :utm_data, :jsonb, null: false, default: {} unless column_exists?(:deals, :utm_data)
    add_column :deals, :custom_attributes, :jsonb, null: false, default: {} unless column_exists?(:deals, :custom_attributes)

    add_index :deals, [:account_id, :pipeline_id] unless index_exists?(:deals, [:account_id, :pipeline_id])
    add_index :deals, [:account_id, :status] unless index_exists?(:deals, [:account_id, :status])
    add_index :deals, [:account_id, :assignee_id] unless index_exists?(:deals, [:account_id, :assignee_id])
    add_index :deals, [:pipeline_stage_id, :status] unless index_exists?(:deals, [:pipeline_stage_id, :status])

    add_check_constraint :deals, "status IN ('open', 'won', 'lost')", name: 'deals_status_values' unless check_constraint_exists?(:deals, name: 'deals_status_values')
    add_check_constraint :deals, 'probability >= 0 AND probability <= 100', name: 'deals_probability_range' unless check_constraint_exists?(:deals, name: 'deals_probability_range')
    add_check_constraint :deals, 'priority_stars >= 0 AND priority_stars <= 3', name: 'deals_priority_stars_range' unless check_constraint_exists?(:deals, name: 'deals_priority_stars_range')
  end

  def create_deals_table
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
      t.text :notes
      t.date :expected_close_date
      t.string :status, null: false, default: 'open'
      t.timestamps
    end
  end

  def ensure_crm_activities
    return if table_exists?(:crm_activities)

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
  end

  def ensure_crm_events
    return if table_exists?(:crm_events)

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
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
