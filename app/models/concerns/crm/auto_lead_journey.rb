module Crm::AutoLeadJourney
  extend ActiveSupport::Concern

  included do
    enum :crm_auto_lead_state, { ineligible: 0, eligible: 1, processed: 2, closed: 3 }, prefix: :crm_auto_lead

    before_create :initialize_crm_auto_lead_journey
    before_update :close_crm_auto_lead_journey, if: -> { will_save_change_to_status? && resolved? }
  end

  private

  def initialize_crm_auto_lead_journey
    # Snapshot activation at creation, never reconstruct eligibility from historical messages.
    # The account lock serializes this snapshot with settings updates.
    persisted_account = Account.lock.find(account_id)
    self.crm_auto_lead_state = if persisted_account.crm_auto_lead_enabled == true
                                 resolved? ? :closed : :eligible
                               else
                                 :ineligible
                               end
  end

  def close_crm_auto_lead_journey
    self.crm_auto_lead_state = :closed unless crm_auto_lead_ineligible?
  end
end
