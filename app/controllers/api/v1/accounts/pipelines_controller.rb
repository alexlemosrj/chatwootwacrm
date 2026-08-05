class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    Pipeline.ensure_default_for!(Current.account)
    @pipelines = Current.account.pipelines.includes(:pipeline_stages).order(:id)
  end

  def show; end

  def create
    @pipeline = Current.account.pipelines.create!(pipeline_params)
    Pipeline::DEFAULT_STAGES.each { |attrs| @pipeline.pipeline_stages.create!(attrs) }
    @pipeline.reload
  end

  def update
    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name)
  end
end
