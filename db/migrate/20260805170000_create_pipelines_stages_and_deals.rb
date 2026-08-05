class CreatePipelinesStagesAndDeals < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :pipelines, [:account_id, :name]

    create_table :pipeline_stages do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.string :color, null: false, default: '#3b82f6'
      t.timestamps
    end
    add_index :pipeline_stages, [:pipeline_id, :position]

    create_table :deals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: true
      t.references :pipeline_stage, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.decimal :value, precision: 12, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.text :notes
      t.date :expected_close_date
      t.string :status, null: false, default: 'open'
      t.timestamps
    end
    add_index :deals, [:account_id, :pipeline_id]
    add_index :deals, [:account_id, :status]
    add_index :deals, :pipeline_stage_id
  end
end
