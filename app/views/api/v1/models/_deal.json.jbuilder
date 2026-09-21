json.id resource.id
json.account_id resource.account_id
json.pipeline_id resource.pipeline_id
json.pipeline_stage_id resource.pipeline_stage_id
json.contact_id resource.contact_id
json.conversation_id resource.conversation_id
json.assignee_id resource.assignee_id
json.title resource.title
json.value resource.value
json.currency resource.currency
json.expected_revenue resource.expected_revenue
json.probability resource.probability
json.priority_stars resource.priority_stars
json.expected_close_date resource.expected_close_date
json.status resource.status
json.notes resource.notes
json.campaign_source resource.campaign_source
json.utm_data resource.utm_data
json.custom_attributes resource.custom_attributes
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i

if resource.contact
  json.contact do
    json.id resource.contact.id
    json.name resource.contact.name
    json.phone_number resource.contact.phone_number
    json.email resource.contact.email
    json.thumbnail resource.contact.thumbnail
  end
end

if resource.assignee
  json.assignee do
    json.id resource.assignee.id
    json.name resource.assignee.name
    json.avatar_url resource.assignee.avatar_url
  end
end
