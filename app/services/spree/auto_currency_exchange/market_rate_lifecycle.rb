# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class MarketRateLifecycle
      class << self
        def refresh_later(market)
          return unless Spree::AutoCurrencyExchange.configuration.enabled

          store_id = market.respond_to?(:store_id) ? market.store_id : market.id
          RefreshRatesJob.perform_later(store_id)
        rescue StandardError => error
          Rails.logger.error("[Spree Auto Currency Exchange] Could not enqueue market rate refresh: #{error.message}")
        end

        def remove_unused_currency_rates(store_id:, currency:)
          code = currency.to_s.upcase
          store = Spree::Store.find_by(id: store_id)
          return unless store
          return if store.markets.where(currency: code).exists?
          return if OriginalCurrency.table_exists? && OriginalCurrency.where(store_id: store_id, currency: code).exists?
          return if source_price_exists?(store_id, code)

          Rate.where(store_id: store_id, currency: code).where.not(base_currency: code).delete_all
        rescue StandardError => error
          Rails.logger.error("[Spree Auto Currency Exchange] Could not remove market rates: #{error.message}")
        end

        private

        def source_price_exists?(store_id, currency)
          Spree::Price.base_prices.joins(variant: :product)
                     .where(spree_products: { store_id: store_id }, currency: currency)
                     .where.not(amount: nil)
                     .exists?
        end
      end
    end
  end
end
