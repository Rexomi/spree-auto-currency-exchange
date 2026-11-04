# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Refresh
      Result = Struct.new(:stores_processed, :rates_saved, keyword_init: true)

      RATE_INDEX = "idx_spree_auto_exchange_rates_unique"

      def initialize(client: FrankfurterClient.new)
        @client = client
        @result = Result.new(stores_processed: 0, rates_saved: 0)
      end

      # Refreshes central store/base-currency rates only. Product and price
      # writes are intentionally absent; conversion happens when Spree resolves
      # a price for the customer's selected currency.
      def call(store_ids: nil)
        plans = store_plans(store_ids)

        ActiveRecord::Base.transaction do
          plans.each { |plan| save_rates(plan) }
        end

        @result
      end

      private

      StorePlan = Struct.new(:store, :base_currency, :rate_set, keyword_init: true)

      def store_plans(store_ids)
        stores = Spree::Store.all
        stores = stores.where(id: store_ids) if store_ids

        stores.find_each.map do |store|
          base = normalize_currency(store.default_currency)
          StorePlan.new(store: store, base_currency: base, rate_set: @client.fetch_all(base_currency: base))
        end
      end

      def save_rates(plan)
        current_store = Spree::Store.lock.find(plan.store.id)
        return unless normalize_currency(current_store.default_currency) == plan.base_currency

        now = Time.current
        rates = plan.rate_set.rates
        rows = rates.map do |currency, rate|
          rate_attributes(plan, currency, rate, now)
        end
        # The identity rate also marks that this store/base pair has completed
        # a full provider snapshot. The scheduler uses it for one-time bootstrap.
        rows << rate_attributes(plan, plan.base_currency, BigDecimal("1"), now)

        Rate.upsert_all(rows, unique_by: RATE_INDEX)

        expected_currencies = rows.map { |row| row.fetch(:currency) }
        Rate.where(store_id: plan.store.id, base_currency: plan.base_currency)
            .where.not(currency: expected_currencies)
            .delete_all
        # A store can change its default currency. Once a complete snapshot for
        # the new base is saved, discard snapshots from the previous base so
        # there is only one active rate table per store.
        Rate.where(store_id: plan.store.id).where.not(base_currency: plan.base_currency).delete_all

        @result.stores_processed += 1
        @result.rates_saved += rows.length
      end

      def rate_attributes(plan, currency, rate, now)
        {
          store_id: plan.store.id,
          base_currency: plan.base_currency,
          currency: currency,
          rate: rate,
          observed_on: plan.rate_set.observed_on,
          fetched_at: plan.rate_set.fetched_at,
          created_at: now,
          updated_at: now
        }
      end

      def normalize_currency(currency)
        value = currency.to_s.upcase
        unless value.match?(/\A[A-Z]{3}\z/)
          raise ConfigurationError, "Store base currency must be a three-letter ISO code"
        end

        value
      end
    end
  end
end
