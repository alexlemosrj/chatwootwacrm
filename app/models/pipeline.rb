# frozen_string_literal: true

class Pipeline < ApplicationRecord
  belongs_to :account
  has_many :pipeline_stages, -> { order(:position) }, dependent: :destroy, inverse_of: :pipeline
  has_many :deals, dependent: :destroy

  validates :name, presence: true

  DEFAULT_STAGES = [
    { name: 'New Lead', color: '#94a3b8', position: 0 },
    { name: 'Qualified', color: '#3b82f6', position: 1 },
    { name: 'Proposal Sent', color: '#8b5cf6', position: 2 },
    { name: 'Negotiation', color: '#f59e0b', position: 3 },
    { name: 'Won', color: '#22c55e', position: 4 }
  ].freeze

  def self.ensure_default_for!(account)
    return account.pipelines.first if account.pipelines.exists?

    pipeline = account.pipelines.create!(name: 'Sales Pipeline')
    DEFAULT_STAGES.each do |attrs|
      pipeline.pipeline_stages.create!(attrs)
    end
    pipeline
  end
end
