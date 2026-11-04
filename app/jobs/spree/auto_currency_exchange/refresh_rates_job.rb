# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class RefreshRatesJob < ActiveJob::Base
      queue_as :default

      def perform(store_id)
        Refresh.new.call(store_ids: [store_id])
      end
    end
  end
end
