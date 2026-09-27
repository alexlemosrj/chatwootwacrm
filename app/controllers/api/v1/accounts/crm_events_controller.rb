class Api::V1::Accounts::CrmEventsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    @crm_events = policy_scope(Current.account.crm_events).includes(:actor, :deal, :contact)
    @crm_events = @crm_events.where(deal_id: params[:deal_id]) if params[:deal_id].present?
    @crm_events = @crm_events.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    @crm_events = @crm_events.order(created_at: :desc, id: :desc).limit(200)
  end
end
