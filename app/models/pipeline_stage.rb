# frozen_string_literal: true

class PipelineStage < ApplicationRecord
  belongs_to :pipeline
  has_many :deals, dependent: :restrict_with_error

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :color, presence: true
  validates :default_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :cannot_be_won_and_lost

  delegate :account, to: :pipeline

  private

  def cannot_be_won_and_lost
    errors.add(:base, 'stage cannot be both won and lost') if is_won? && is_lost?
  end
end
