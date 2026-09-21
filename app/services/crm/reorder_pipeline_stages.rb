# frozen_string_literal: true

class Crm::ReorderPipelineStages
  Result = Data.define(:success, :error)

  def self.call(pipeline, stages)
    new(pipeline, stages).call
  end

  def initialize(pipeline, stages)
    @pipeline = pipeline
    @stages = stages
  end

  def call
    return failure('Reordering must include every stage from this pipeline exactly once') unless valid_stage_ids?
    return failure('Stage positions must be contiguous and unique') unless valid_positions?

    PipelineStage.transaction do
      locked_stages.each_value do |stage|
        stage.update!(position: stage.position + 100_000)
      end

      stages.each do |item|
        locked_stages.fetch(item[:id].to_i).update!(position: item[:position].to_i)
      end
    end

    Result.new(success: true, error: nil)
  end

  private

  attr_reader :pipeline, :stages

  def requested_ids
    @requested_ids ||= stages.map { |item| item[:id].to_i }
  end

  def pipeline_ids
    @pipeline_ids ||= pipeline.pipeline_stages.order(:position).pluck(:id)
  end

  def valid_stage_ids?
    requested_ids.sort == pipeline_ids.sort
  end

  def valid_positions?
    stages.map { |item| item[:position].to_i }.sort == (0...pipeline_ids.length).to_a
  end

  def locked_stages
    @locked_stages ||= pipeline.pipeline_stages.lock.index_by(&:id)
  end

  def failure(message)
    Result.new(success: false, error: message)
  end
end
