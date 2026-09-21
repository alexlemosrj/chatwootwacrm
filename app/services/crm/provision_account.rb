# frozen_string_literal: true

module Crm
  class ProvisionAccount
    def self.call(account)
      new(account).call
    end

    def initialize(account)
      @account = account
    end

    def call
      account.with_lock do
        pipeline = account.pipelines.find_by(is_default: true) || account.pipelines.order(:id).first

        if pipeline.nil?
          pipeline = account.pipelines.create!(name: 'Funil de Vendas', is_default: true)
        elsif !pipeline.is_default?
          pipeline.update!(is_default: true)
        end

        provision_default_stages(pipeline) if pipeline.pipeline_stages.empty?
        pipeline
      end
    end

    private

    attr_reader :account

    def provision_default_stages(pipeline)
      Pipeline::DEFAULT_STAGES.each do |attributes|
        pipeline.pipeline_stages.create!(attributes)
      end
    end
  end
end
