# frozen_string_literal: true

class Deal < ApplicationRecord
  STATUSES = %w[open won lost].freeze

  belongs_to :account
  belongs_to :pipeline
  belongs_to :pipeline_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :crm_activities, dependent: :destroy
  has_many :crm_events, dependent: :nullify

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true
  validates :value, :expected_revenue, numericality: { greater_than_or_equal_to: 0 }
  validates :probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :priority_stars, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 3 }

  validate :pipeline_belongs_to_account
  validate :stage_belongs_to_pipeline
  validate :contact_belongs_to_account
  validate :conversation_belongs_to_account
  validate :assignee_belongs_to_account

  scope :open_status, -> { where(status: 'open') }

  private

  def pipeline_belongs_to_account
    return if pipeline.blank? || account.blank? || pipeline.account_id == account_id

    errors.add(:pipeline, 'must belong to the same account')
  end

  def stage_belongs_to_pipeline
    return if pipeline_stage.blank? || pipeline.blank? || pipeline_stage.pipeline_id == pipeline_id

    errors.add(:pipeline_stage, 'must belong to the selected pipeline')
  end

  def contact_belongs_to_account
    return if contact.blank? || account.blank? || contact.account_id == account_id

    errors.add(:contact, 'must belong to the same account')
  end

  def conversation_belongs_to_account
    return if conversation.blank? || account.blank? || conversation.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end

  def assignee_belongs_to_account
    return if assignee.blank? || account.blank? || account.users.exists?(id: assignee_id)

    errors.add(:assignee, 'must belong to the same account')
  end
end
