# frozen_string_literal: true

class PipelineStage < ApplicationRecord
  belongs_to :pipeline
  has_many :deals, dependent: :restrict_with_error

  validates :name, presence: true
  validates :position, presence: true
  validates :color, presence: true

  delegate :account, to: :pipeline
end
