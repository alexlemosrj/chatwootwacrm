class Api::V1::Accounts::PipelineStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @pipeline_stages = @pipeline.pipeline_stages
  end

  def create
    @pipeline_stage = @pipeline.pipeline_stages.create!(stage_params)
  end

  def update
    @pipeline_stage.update!(stage_params)
  end

  def reorder
    stages = params.require(:stages)
    requested_ids = stages.map { |item| item[:id].to_i }
    pipeline_ids = @pipeline.pipeline_stages.order(:position).pluck(:id)

    unless requested_ids.sort == pipeline_ids.sort
      render json: { error: 'Reordering must include every stage from this pipeline exactly once' }, status: :unprocessable_entity
      return
    end

    positions = stages.map { |item| item[:position].to_i }
    unless positions.sort == (0...pipeline_ids.length).to_a
      render json: { error: 'Stage positions must be contiguous and unique' }, status: :unprocessable_entity
      return
    end

    PipelineStage.transaction do
      locked_stages = @pipeline.pipeline_stages.lock.index_by(&:id)

      # Move every row out of the final position range first so swapping
      # positions cannot violate the unique (pipeline_id, position) index.
      locked_stages.each_value do |stage|
        stage.update_columns(position: stage.position + 100_000)
      end

      stages.each do |item|
        locked_stages.fetch(item[:id].to_i).update!(position: item[:position].to_i)
      end
    end

    @pipeline_stages = @pipeline.pipeline_stages.reload
    render :index
  end

  def destroy
    if @pipeline_stage.deals.exists?
      render json: { error: 'Stage has deals; move or delete them first' }, status: :unprocessable_entity
      return
    end

    @pipeline_stage.destroy!
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end

  def fetch_stage
    @pipeline_stage = @pipeline.pipeline_stages.find(params[:id])
  end

  def stage_params
    params.require(:pipeline_stage).permit(:name, :position, :color, :default_probability, :is_won, :is_lost)
  end

  def check_authorization
    authorize(PipelineStage)
  end
end
