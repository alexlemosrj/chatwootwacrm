# frozen_string_literal: true

class CrmEvent < ApplicationRecord
  belongs_to :account
  belongs_to :deal, optional: true
  belongs_to :contact, optional: true
  belongs_to :actor, class_name: 'User', optional: true

  validates :event_type, presence: true
  validate :references_belong_to_account
  validate :actor_belongs_to_account, if: -> { new_record? || actor_id_changed? }
  before_create :snapshot_actor

  private

  def references_belong_to_account
    errors.add(:deal, 'must belong to the same account') if deal.present? && deal.account_id != account_id
    errors.add(:contact, 'must belong to the same account') if contact.present? && contact.account_id != account_id
  end

  def actor_belongs_to_account
    errors.add(:actor, 'must belong to the same account') if actor.present? && !account.users.exists?(id: actor_id)
  end

  def snapshot_actor
    self.actor_snapshot = actor.slice(:id, :name) if actor
  end
end
