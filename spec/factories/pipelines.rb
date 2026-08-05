# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline do
    account
    sequence(:name) { |n| "Pipeline #{n}" }
  end

  factory :pipeline_stage do
    pipeline
    sequence(:name) { |n| "Stage #{n}" }
    sequence(:position)
    color { '#3b82f6' }
  end

  factory :deal do
    account
    pipeline
    pipeline_stage
    sequence(:title) { |n| "Deal #{n}" }
    value { 1000 }
    currency { 'USD' }
    status { 'open' }

    after(:build) do |deal|
      deal.pipeline ||= deal.pipeline_stage&.pipeline
      deal.account ||= deal.pipeline&.account
    end
  end
end
