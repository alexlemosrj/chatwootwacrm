class Api::V1::Accounts::CrmActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_activity, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @crm_activities = policy_scope(Current.account.crm_activities).includes(:deal, :contact, :assignee)
    @crm_activities = @crm_activities.where(deal_id: params[:deal_id]) if params[:deal_id].present?
    @crm_activities = @crm_activities.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    @crm_activities = @crm_activities.where(status: params[:status]) if params[:status].present?
    @crm_activities = @crm_activities.order(Arel.sql('due_at ASC NULLS LAST'), :id)
  end

  def show; end

  def create
    @crm_activity = Current.account.crm_activities.create!(activity_params)
    log_event!('activity_created')
  end

  def update
    @crm_activity.update!(activity_params)
    log_event!('activity_updated')
  end

  def destroy
    log_event!('activity_deleted')
    @crm_activity.destroy!
    head :ok
  end

  private

  def fetch_activity
    @crm_activity = Current.account.crm_activities.find(params[:id])
  end

  def activity_params
    params.require(:crm_activity).permit(
      :deal_id, :contact_id, :assignee_id, :activity_type, :title,
      :start_at, :due_at, :completed_at, :status, :notes
    )
  end

  def log_event!(event_type)
    Current.account.crm_events.create!(
      deal: @crm_activity.deal,
      contact: @crm_activity.contact,
      actor: Current.user,
      event_type: event_type,
      metadata: {
        activity_id: @crm_activity.id,
        activity_type: @crm_activity.activity_type,
        title: @crm_activity.title,
        status: @crm_activity.status,
        due_at: @crm_activity.due_at
      }
    )
  end
end
