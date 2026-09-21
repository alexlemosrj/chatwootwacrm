# frozen_string_literal: true

class Pipeline < ApplicationRecord
  DEFAULT_STAGES = [
    { name: 'Novo Lead', color: '#94a3b8', position: 0, default_probability: 10 },
    { name: 'Qualificado', color: '#3b82f6', position: 1, default_probability: 30 },
    { name: 'Proposta', color: '#8b5cf6', position: 2, default_probability: 50 },
    { name: 'Negociação', color: '#f59e0b', position: 3, default_probability: 70 },
    { name: 'Ganho', color: '#22c55e', position: 4, default_probability: 100, is_won: true }
  ].freeze

  belongs_to :account
  has_many :pipeline_stages, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :pipeline
  has_many :deals, dependent: :restrict_with_error

  validates :name, presence: true

  scope :default_first, -> { order(is_default: :desc, id: :asc) }
end
