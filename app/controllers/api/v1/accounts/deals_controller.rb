class Api::V1::Accounts::DealsController < Api::V1::Accounts::BaseController
  before_action :fetch_deal, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @deals = Current.account.deals.includes(:contact, :assignee, :pipeline_stage, :pipeline)
    @deals = @deals.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    @deals = @deals.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    @deals = @deals.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
  end

  def show; end

  def create
    @deal = Current.account.deals.create!(deal_params)
  end

  def update
    @deal.update!(deal_params)
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
      :title, :value, :currency, :notes, :expected_close_date, :status,
      :pipeline_id, :pipeline_stage_id, :contact_id, :conversation_id, :assignee_id
    )
  end
end
