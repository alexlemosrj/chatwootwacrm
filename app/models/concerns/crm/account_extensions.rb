# frozen_string_literal: true

module Crm::AccountExtensions
  extend ActiveSupport::Concern

  included do
    has_many :pipelines, dependent: :destroy_async
    has_many :deals, dependent: :destroy_async
    has_many :crm_activities, dependent: :destroy_async
    has_many :crm_events, dependent: :destroy_async

    after_create_commit :provision_crm
  end

  private

  def provision_crm
    Crm::ProvisionAccount.call(self)
  rescue StandardError => e
    Rails.logger.error("CRM provisioning failed for account #{id}: #{e.class} - #{e.message}")
  end
end
