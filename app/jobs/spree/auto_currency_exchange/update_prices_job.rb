# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class UpdatePricesJob < ActiveJob::Base
      queue_as :default

      def perform(scheduled_at)
        Scheduler.run(scheduled_at)
      end
    end
  end
end
