class CrmActivityPolicy < ApplicationPolicy
  def index? = account_member?
  def show? = account_member?
  def create? = account_member?
  def update? = account_member?
  def destroy? = account_member?

  private

  def account_member?
    @account_user&.administrator? || @account_user&.agent?
  end
end
