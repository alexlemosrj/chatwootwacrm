class DealPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    create?
  end

  def destroy?
    @account_user.administrator? || @account_user.agent?
  end
end
