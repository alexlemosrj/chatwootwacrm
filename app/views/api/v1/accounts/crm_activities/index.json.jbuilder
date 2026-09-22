json.payload do
  json.array! @crm_activities do |activity|
    json.partial! 'api/v1/models/crm_activity', formats: [:json], resource: activity
  end
end
