require 'rails_helper'

RSpec.describe 'CRM contact integrity', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:pipeline) { account.pipelines.find_by!(is_default: true) }
  let(:deal) do
    account.deals.create!(contact: contact, pipeline: pipeline, pipeline_stage: pipeline.pipeline_stages.first, title: 'Contact deal')
  end
  let(:activity) { account.crm_activities.create!(contact: contact, title: 'Contact activity', activity_type: 'task') }
  let(:event) { account.crm_events.create!(contact: contact, event_type: 'contact_history', metadata: { note: 'Preserve history' }) }

  {
    'Deal only' => [:deal],
    'Activity only' => [:activity],
    'Event only' => [:event],
    'Deal + Activity + Event' => [:deal, :activity, :event]
  }.each do |label, references|
    context "with #{label}" do
      let!(:crm_records) { references.map { |reference| public_send(reference) } }

      it 'rejects contact deletion with a controlled response and preserves every reference' do
        snapshots = crm_records.map(&:attributes)

        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.fetch('error')).to eq(I18n.t('crm.contact_has_history'))

        expect(Contact.exists?(contact.id)).to be(true)
        expect(crm_records.map { |record| record.reload.attributes }).to eq(snapshots)
        expect(crm_records.map { |record| record.reload.contact_id }).to all(eq(contact.id))
      end

      it 'transfers all CRM references and CE conversations during the real contact merge' do
        base_contact = create(:contact, account: account)
        base_deal = account.deals.create!(contact: base_contact, pipeline: pipeline,
                                          pipeline_stage: pipeline.pipeline_stages.first, title: 'Base deal')
        base_activity = account.crm_activities.create!(contact: base_contact, title: 'Base activity', activity_type: 'task')
        base_event = account.crm_events.create!(contact: base_contact, event_type: 'base_history', metadata: { note: 'Base history' })
        conversation = create(:conversation, account: account, contact: contact)
        message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: contact)
        records = crm_records + [base_deal, base_activity, base_event]
        snapshots = records.map(&:attributes)

        post "/api/v1/accounts/#{account.id}/actions/contact_merge",
             params: { base_contact_id: base_contact.id, mergee_contact_id: contact.id },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok), response.body

        expect(Contact.exists?(contact.id)).to be(false)
        expect(Contact.exists?(base_contact.id)).to be(true)
        expect(records.map { |record| record.reload.attributes }).to eq(snapshots.map { |attrs| attrs.merge('contact_id' => base_contact.id) })
        expect(conversation.reload.contact_id).to eq(base_contact.id)
        expect(conversation.contact_inbox.reload.contact_id).to eq(base_contact.id)
        expect(message.reload.sender).to eq(base_contact)
      end
    end
  end

  it 'rolls back CRM and CE transfers if the surviving contact cannot be saved' do
    base_contact = create(:contact, account: account)
    base_contact.update_column(:phone_number, 'invalid') # rubocop:disable Rails/SkipsModelValidations
    records = [deal, activity, event]
    snapshots = records.map(&:attributes)
    conversation = create(:conversation, account: account, contact: contact)

    post "/api/v1/accounts/#{account.id}/actions/contact_merge",
         params: { base_contact_id: base_contact.id, mergee_contact_id: contact.id },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Contact.exists?(contact.id)).to be(true)
    expect(records.map { |record| record.reload.attributes }).to eq(snapshots)
    expect(conversation.reload.contact_id).to eq(contact.id)
    expect(conversation.contact_inbox.reload.contact_id).to eq(contact.id)
  end
end
