# frozen_string_literal: true

class CrmActivity < ApplicationRecord
  ACTIVITY_TYPES = %w[call whatsapp meeting followup task email].freeze
  STATUSES = %w[planned completed cancelled].freeze

  belongs_to :account
  belongs_to :deal, optional: true
  belongs_to :contact, optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  validates :title, presence: true
  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  validates :status, inclusion: { in: STATUSES }

  validate :deal_belongs_to_account
  validate :contact_belongs_to_account
  validate :assignee_belongs_to_account

  before_validation :sync_completed_at

  scope :planned, -> { where(status: 'planned') }
  scope :overdue, -> { planned.where('due_at < ?', Time.current) }

  private

  def sync_completed_at
    if status == 'completed'
      self.completed_at ||= Time.current
    else
      self.completed_at = nil
    end
  end

  def deal_belongs_to_account
    return if deal.blank? || account.blank? || deal.account_id == account_id

    errors.add(:deal, 'must belong to the same account')
  end

  def contact_belongs_to_account
    return if contact.blank? || account.blank? || contact.account_id == account_id

    errors.add(:contact, 'must belong to the same account')
  end

  def assignee_belongs_to_account
    return if assignee.blank? || account.blank? || account.users.exists?(id: assignee_id)

    errors.add(:assignee, 'must belong to the same account')
  end
end
