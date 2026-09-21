# frozen_string_literal: true

class CrmEvent < ApplicationRecord
  belongs_to :account
  belongs_to :deal, optional: true
  belongs_to :contact, optional: true
  belongs_to :actor, class_name: 'User', optional: true

  validates :event_type, presence: true
  validate :references_belong_to_account

  private

  def references_belong_to_account
    errors.add(:deal, 'must belong to the same account') if deal.present? && deal.account_id != account_id
    errors.add(:contact, 'must belong to the same account') if contact.present? && contact.account_id != account_id
    errors.add(:actor, 'must belong to the same account') if actor.present? && !account.users.exists?(id: actor_id)
  end
end
