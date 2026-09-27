# frozen_string_literal: true

module Crm::ContactExtensions
  extend ActiveSupport::Concern

  included do
    has_many :deals, dependent: :restrict_with_error
    has_many :crm_activities, dependent: :restrict_with_error
    has_many :crm_events, dependent: :restrict_with_error
  end
end
