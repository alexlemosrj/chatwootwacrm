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
    result = Crm::ReorderPipelineStages.call(@pipeline, params.require(:stages))
    unless result.success?
      render json: { error: result.error }, status: :unprocessable_entity
      return
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
