class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    Crm::ProvisionAccount.call(Current.account)
    @pipelines = policy_scope(Current.account.pipelines).includes(:pipeline_stages).default_first
  end

  def show; end

  def create
    attributes = pipeline_params
    @pipeline = Current.account.pipelines.create!(attributes.except(:is_default, :with_default_stages))

    with_default_stages = attributes[:with_default_stages].nil? ||
                          ActiveModel::Type::Boolean.new.cast(attributes[:with_default_stages])
    Pipeline::DEFAULT_STAGES.each { |stage_attributes| @pipeline.pipeline_stages.create!(stage_attributes) } if with_default_stages

    set_as_default!(@pipeline) if ActiveModel::Type::Boolean.new.cast(attributes[:is_default])
    @pipeline.reload
  end

  def update
    @pipeline.update!(pipeline_params.except(:is_default))
    set_as_default!(@pipeline) if ActiveModel::Type::Boolean.new.cast(pipeline_params[:is_default])
    @pipeline.reload
  end

  def destroy
    if Current.account.pipelines.where.not(id: @pipeline.id).none?
      render json: { error: 'At least one pipeline must remain' }, status: :unprocessable_entity
      return
    end

    was_default = @pipeline.is_default?
    @pipeline.destroy!
    set_as_default!(Current.account.pipelines.order(:id).first) if was_default
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :is_default, :with_default_stages)
  end

  def set_as_default!(pipeline)
    Current.account.pipelines.transaction do
      Current.account.pipelines.where.not(id: pipeline.id).update_all(is_default: false)
      pipeline.update!(is_default: true) unless pipeline.is_default?
    end
  end
end
