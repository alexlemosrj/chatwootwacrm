json.payload do
  json.array! @crm_events do |event|
    json.partial! 'api/v1/models/crm_event', formats: [:json], resource: event
  end
end
