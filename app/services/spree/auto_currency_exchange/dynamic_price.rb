# frozen_string_literal: true

require "money"

module Spree
  module AutoCurrencyExchange
    class DynamicPrice
      def initialize(variant:, currency:, store: nil, original_price_resolver: nil, rate_converter: nil, price_factory: nil)
        @variant = variant
        @currency = currency.to_s.upcase
        @store = store || variant.product&.store || Spree::Current.store || Spree::Store.default
        @original_price_resolver = original_price_resolver || OriginalPriceResolver.new(store: @store, variant: @variant)
        @rate_converter = rate_converter || RateConverter.new(store: @store)
        @price_factory = price_factory || ->(attributes) { Spree::Price.new(attributes) }
      end

      # Returns an in-memory Spree::Price when no merchant price or override
      # applies. No currency-specific Spree::Price record is created.
      def resolve(fallback_price: nil)
        legacy_generated = legacy_generated_price?(fallback_price)
        return empty_price if legacy_generated && !market_currency?
        return unless market_currency?

        override = active_override
        return build_override_price(override) if override
        return fallback_price if fallback_price&.amount.present? && !legacy_generated

        source_price, source_currency = @original_price_resolver.call
        return empty_price if legacy_generated && (!source_price || !source_currency)
        return unless source_price && source_currency
        return source_price if source_currency == @currency

        rate = @rate_converter.call(from_currency: source_currency, to_currency: @currency)
        return empty_price if legacy_generated && !rate&.positive?
        return unless rate&.positive?

        markup = Spree::AutoCurrencyExchange.configuration.markup_for(@currency)
        calculator = PriceCalculator.new(
          currency: @currency,
          rate: rate,
          markup: markup,
          precision: currency_precision(@currency)
        )

        price = build_price({
          variant_id: @variant.id,
          currency: @currency,
          amount: calculator.convert(source_price.amount),
          compare_at_amount: calculator.convert(source_price.compare_at_amount),
          price_list_id: nil
        })
        attach_snapshot(price, rate: rate, source_price: source_price, source_currency: source_currency)
        price
      end

      private

      def market_currency?
        return false if @store.blank? || @currency.blank?

        if @store.respond_to?(:has_markets?) && @store.has_markets?
          @store.markets.where(currency: @currency).exists?
        else
          @store.supported_currencies_list.any? { |item| item.iso_code == @currency }
        end
      end

      def active_override
        return unless PriceOverride.table_exists?

        PriceOverride.active.find_by(store_id: @store.id, variant_id: @variant.id, currency: @currency)
      end

      def legacy_generated_price?(price)
        return false unless price&.amount.present?
        return false if @store.blank?
        return false unless price.respond_to?(:persisted?) && price.persisted?
        return false unless ConvertedPrice.table_exists?

        tracking = ConvertedPrice.find_by(
          store_id: @store.id,
          variant_id: @variant.id,
          currency: @currency,
          price_id: price.id
        )
        tracking.present? && !tracking.locked? && tracking.price_matches_snapshot?(price)
      end

      def empty_price
        build_price({ variant_id: @variant.id, currency: @currency, amount: nil, price_list_id: nil })
      end

      def build_override_price(override)
        price = build_price({
          variant_id: @variant.id,
          currency: @currency,
          amount: override.amount,
          compare_at_amount: override.compare_at_amount,
          price_list_id: nil
        })
        price.auto_currency_exchange_manual_override = true if price.respond_to?(:auto_currency_exchange_manual_override=)
        price
      end

      def build_price(attributes)
        if defined?(Spree::Price) && Spree::Price.respond_to?(:column_names) && Spree::Price.column_names.include?("min_quantity")
          attributes[:min_quantity] = 1
        end

        @price_factory.call(attributes)
      end

      def currency_precision(currency)
        info = ::Money::Currency.find(currency)
        return 2 unless info&.subunit_to_unit&.positive?

        Math.log10(info.subunit_to_unit).round
      end

      def attach_snapshot(price, rate:, source_price:, source_currency:)
        return unless price.respond_to?(:auto_currency_exchange_rate=)

        price.auto_currency_exchange_rate = rate
        price.auto_currency_exchange_source_currency = source_currency
        price.auto_currency_exchange_source_amount = source_price.amount
      end
    end
  end
end
