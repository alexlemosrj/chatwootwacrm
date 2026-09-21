class Api::V1::Accounts::DealsController < Api::V1::Accounts::BaseController
  before_action :fetch_deal, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @deals = policy_scope(Current.account.deals).includes(:contact, :conversation, :assignee, :pipeline, :pipeline_stage)
    @deals = @deals.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    @deals = @deals.where(pipeline_stage_id: params[:pipeline_stage_id]) if params[:pipeline_stage_id].present?
    @deals = @deals.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    @deals = @deals.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    @deals = @deals.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    @deals = @deals.where(status: params[:status]) if params[:status].present?
  end

  def show; end

  def create
    attributes = deal_params
    stage = PipelineStage.joins(:pipeline)
                         .where(id: attributes[:pipeline_stage_id], pipelines: { account_id: Current.account.id })
                         .first
    attributes[:probability] = stage.default_probability if stage && attributes[:probability].blank?
    @deal = Current.account.deals.create!(attributes)
    create_event!('deal_created', to: deal_snapshot(@deal))
  end

  def update
    before = deal_snapshot(@deal)
    @deal.update!(deal_params)
    after = deal_snapshot(@deal)

    log_change_events(before, after) if before != after
  end

  def destroy
    @deal.destroy!
    head :ok
  end

  private

  def fetch_deal
    @deal = Current.account.deals.find(params[:id])
  end

  def deal_params
    params.require(:deal).permit(
      :title, :value, :currency, :expected_revenue, :probability, :priority_stars,
      :expected_close_date, :status, :notes, :campaign_source,
      :pipeline_id, :pipeline_stage_id, :contact_id, :conversation_id, :assignee_id,
      utm_data: {}, custom_attributes: {}
    )
  end

  def deal_snapshot(deal)
    deal.attributes.slice(
      'pipeline_id', 'pipeline_stage_id', 'assignee_id', 'title', 'value', 'currency',
      'expected_revenue', 'probability', 'priority_stars', 'expected_close_date',
      'status', 'campaign_source'
    )
  end

  def log_change_events(before, after)
    create_event!('stage_changed', from: before['pipeline_stage_id'], to: after['pipeline_stage_id']) if before['pipeline_stage_id'] != after['pipeline_stage_id']
    create_event!('status_changed', from: before['status'], to: after['status']) if before['status'] != after['status']
    create_event!('assignment_changed', from: before['assignee_id'], to: after['assignee_id']) if before['assignee_id'] != after['assignee_id']

    ignored_keys = %w[pipeline_stage_id status assignee_id]
    before_other = before.except(*ignored_keys)
    after_other = after.except(*ignored_keys)
    create_event!('deal_updated', from: before_other, to: after_other) if before_other != after_other
  end

  def create_event!(event_type, metadata)
    Current.account.crm_events.create!(
      deal: @deal,
      contact: @deal.contact,
      actor: Current.user,
      event_type: event_type,
      metadata: metadata
    )
  end
end
