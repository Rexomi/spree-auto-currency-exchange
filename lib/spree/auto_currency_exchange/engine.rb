# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Engine < Rails::Engine
      engine_name "spree_auto_currency_exchange"
      isolate_namespace Spree::AutoCurrencyExchange

      initializer "spree_auto_currency_exchange.schedule_daily_update" do |app|
        app.config.after_initialize do
          next unless Spree::AutoCurrencyExchange.configuration.enabled
          next unless defined?(Spree::AutoCurrencyExchange::Schedule)
          next unless Spree::AutoCurrencyExchange::Schedule.table_exists?

          Spree::AutoCurrencyExchange::Scheduler.ensure_scheduled!
        rescue StandardError => error
          app.logger.info("[Spree Auto Currency Exchange] Scheduler not started: #{error.message}")
        end
      end
    end
  end
end
