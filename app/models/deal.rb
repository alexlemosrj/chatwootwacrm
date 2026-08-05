# frozen_string_literal: true

class Deal < ApplicationRecord
  STATUSES = %w[open won lost].freeze

  belongs_to :account
  belongs_to :pipeline
  belongs_to :pipeline_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true
  validates :value, numericality: true

  before_validation :sync_pipeline_from_stage

  scope :open_status, -> { where(status: 'open') }

  private

  def sync_pipeline_from_stage
    return if pipeline_stage.blank?

    self.pipeline_id = pipeline_stage.pipeline_id
  end
end
