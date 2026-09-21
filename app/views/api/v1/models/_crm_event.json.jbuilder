json.id resource.id
json.account_id resource.account_id
json.deal_id resource.deal_id
json.contact_id resource.contact_id
json.actor_id resource.actor_id
json.event_type resource.event_type
json.metadata resource.metadata
json.created_at resource.created_at.to_i

if resource.actor
  json.actor do
    json.id resource.actor.id
    json.name resource.actor.name
    json.avatar_url resource.actor.avatar_url
  end
end
