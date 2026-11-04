# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class RateConverter
      def initialize(store:)
        @store = store
      end

      # All stored quotes share the store's current default currency as their
      # base. Cross rates are derived from that saved snapshot without an API
      # request: (base -> target) / (base -> source).
      def call(from_currency:, to_currency:)
        source = from_currency.to_s.upcase
        target = to_currency.to_s.upcase
        return BigDecimal("1") if source == target

        base = @store.default_currency.to_s.upcase
        source_rate = rate_for(base, source)
        target_rate = rate_for(base, target)
        return unless source_rate && target_rate

        target_rate / source_rate
      end

      private

      def rate_for(base_currency, currency)
        return BigDecimal("1") if base_currency == currency
        return unless Rate.table_exists?

        Rate.find_by(store_id: @store.id, base_currency: base_currency, currency: currency)&.rate
      end
    end
  end
end
