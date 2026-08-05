json.id resource.id
json.account_id resource.account_id
json.name resource.name
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.stages do
  json.array! resource.pipeline_stages do |stage|
    json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage
  end
end
