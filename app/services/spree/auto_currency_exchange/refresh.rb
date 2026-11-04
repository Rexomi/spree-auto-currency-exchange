# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Refresh
      Result = Struct.new(
        :stores_processed, :rates_saved, :prices_created, :prices_updated,
        :overrides_applied, :manual_prices_preserved, :locked_prices_preserved,
        keyword_init: true
      )

      BATCH_SIZE = 500

      def initialize(client: FrankfurterClient.new, configuration: Spree::AutoCurrencyExchange.configuration)
        @client = client
        @configuration = configuration
        @result = Result.new(
          stores_processed: 0, rates_saved: 0, prices_created: 0, prices_updated: 0,
          overrides_applied: 0, manual_prices_preserved: 0, locked_prices_preserved: 0
        )
      end

      def call
        plans = store_plans

        ActiveRecord::Base.transaction do
          plans.each { |plan| apply_store(plan) }
        end

        @result
      end

      private

      StorePlan = Struct.new(:store, :base_currency, :targets, :rate_set, keyword_init: true)

      def store_plans
        Spree::Store.includes(:markets).find_each.map do |store|
          base = normalize_currency(store.default_currency)
          targets = store.markets.map { |market| normalize_currency(market.currency) }.uniq - [base]
          next if targets.empty?

          rate_set = @client.fetch(base_currency: base, currencies: targets)
          missing = targets - rate_set.rates.keys
          raise MissingRateError, "No complete rate set for #{base}: #{missing.join(', ')}" if missing.any?

          StorePlan.new(store: store, base_currency: base, targets: targets, rate_set: rate_set)
        end.compact
      end

      def apply_store(plan)
        plan.rate_set.rates.each do |currency, rate|
          Rate.find_or_initialize_by(
            store_id: plan.store.id,
            base_currency: plan.base_currency,
            currency: currency
          ).update!(rate: rate, observed_on: plan.rate_set.observed_on, fetched_at: plan.rate_set.fetched_at)
          @result.rates_saved += 1
        end

        base_prices_scope(plan.store, plan.base_currency).find_in_batches(batch_size: BATCH_SIZE) do |base_prices|
          apply_price_batch(plan, base_prices)
        end

        @result.stores_processed += 1
      end

      def base_prices_scope(store, currency)
        scope = Spree::Price.joins(variant: :product)
                            .where(spree_products: { store_id: store.id })
                            .where(currency: currency, price_list_id: nil)
        scope = scope.where(min_quantity: 1) if quantity_breaks_supported?
        scope
      end

      def apply_price_batch(plan, base_prices)
        variant_ids = base_prices.map(&:variant_id)
        tracks = ConvertedPrice.where(store_id: plan.store.id, variant_id: variant_ids, currency: plan.targets)
                               .index_by { |record| [record.variant_id, record.currency] }
        overrides = PriceOverride.active.where(store_id: plan.store.id, variant_id: variant_ids, currency: plan.targets)
                                  .index_by { |record| [record.variant_id, record.currency] }
        target_scope = Spree::Price.where(variant_id: variant_ids, currency: plan.targets, price_list_id: nil)
        target_scope = target_scope.where(min_quantity: 1) if quantity_breaks_supported?
        target_prices = target_scope.to_a.index_by { |record| [record.variant_id, record.currency] }

        base_prices.each do |base_price|
          next if base_price.amount.nil?

          plan.targets.each do |currency|
            key = [base_price.variant_id, currency]
            rate = plan.rate_set.rates.fetch(currency)
            calculator = calculator_for(currency, rate)
            converted_amount = calculator.convert(base_price.amount)
            converted_compare_at = calculator.convert(base_price.compare_at_amount)
            tracking = tracks[key]
            target_price = target_prices[key]
            override = overrides[key]

            if override.nil? && tracking.nil? && target_price.present?
              @result.manual_prices_preserved += 1
              next
            end

            if override.nil? && tracking&.locked?
              @result.locked_prices_preserved += 1
              next
            end

            if override.nil? && tracking && target_price && !tracking.price_matches_snapshot?(target_price)
              tracking.update!(locked: true)
              @result.locked_prices_preserved += 1
              next
            end

            amount = override ? override.amount : converted_amount
            compare_at_amount = if override&.compare_at_amount.present?
                                  override.compare_at_amount
                                else
                                  converted_compare_at
                                end
            apply_converted_price(
              store: plan.store,
              base_price: base_price,
              currency: currency,
              rate: rate,
              target_price: target_price,
              tracking: tracking,
              amount: amount,
              compare_at_amount: compare_at_amount,
              override: override
            )

            @result.overrides_applied += 1 if override
          end
        end
      end

      def apply_converted_price(store:, base_price:, currency:, rate:, target_price:, tracking:, amount:, compare_at_amount:, override:)
        is_new = target_price.nil?
        target_price ||= Spree::Price.new(new_price_attributes(base_price.variant_id, currency))
        target_price.assign_attributes(amount: amount, compare_at_amount: compare_at_amount)
        target_price.save!

        tracking ||= ConvertedPrice.new(store: store, variant_id: base_price.variant_id, currency: currency)
        tracking.update!(
          price: target_price,
          amount: target_price.amount,
          compare_at_amount: target_price.compare_at_amount,
          source_amount: base_price.amount,
          source_compare_at_amount: base_price.compare_at_amount,
          source_currency: base_price.currency,
          exchange_rate: rate,
          markup: override ? BigDecimal("0") : @configuration.markup_for(currency),
          locked: false,
          last_updated_at: Time.current
        )

        is_new ? @result.prices_created += 1 : @result.prices_updated += 1
      end

      def new_price_attributes(variant_id, currency)
        attributes = { variant_id: variant_id, currency: currency, price_list_id: nil }
        attributes[:min_quantity] = 1 if quantity_breaks_supported?
        attributes
      end

      def calculator_for(currency, rate)
        PriceCalculator.new(
          currency: currency,
          rate: rate,
          markup: @configuration.markup_for(currency),
          precision: currency_precision(currency)
        )
      end

      def currency_precision(currency)
        currency_info = Money::Currency.find(currency)
        subunit = currency_info&.subunit_to_unit
        return 2 unless subunit && subunit.positive?

        Math.log10(subunit).round
      rescue StandardError
        raise ConfigurationError, "Unknown currency #{currency.inspect}; cannot determine its minor-unit precision"
      end

      def quantity_breaks_supported?
        @quantity_breaks_supported ||= Spree::Price.column_names.include?("min_quantity")
      end

      def normalize_currency(currency)
        value = currency.to_s.upcase
        raise ConfigurationError, "Store and market currencies must be three-letter ISO codes" unless value.match?(/\A[A-Z]{3}\z/)

        value
      end
    end
  end
end
