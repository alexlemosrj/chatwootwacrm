# frozen_string_literal: true

class CascadePipelineStagesOnPipelineDelete < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :pipeline_stages, :pipelines if foreign_key_exists?(:pipeline_stages, :pipelines)
    add_foreign_key :pipeline_stages, :pipelines, on_delete: :cascade
  end

  def down
    remove_foreign_key :pipeline_stages, :pipelines if foreign_key_exists?(:pipeline_stages, :pipelines)
    add_foreign_key :pipeline_stages, :pipelines
  end
end
