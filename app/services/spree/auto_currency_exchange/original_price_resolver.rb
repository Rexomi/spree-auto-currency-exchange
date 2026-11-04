# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class OriginalPriceResolver
      def initialize(store:, variant:)
        @store = store
        @variant = variant
      end

      # Returns [price, currency]. The currency is recorded on first use so a
      # later addition of another price cannot silently change the product's
      # source currency.
      def call
        original = if OriginalCurrency.table_exists?
                     OriginalCurrency.find_by(store_id: @store.id, variant_id: @variant.id)
                   end
        if original
          price = base_price_for(original.currency)
          return [price, original.currency] if price
          return
        end

        default_currency = @store.default_currency.to_s.upcase
        selected = base_price_for(default_currency)
        selected ||= self.class.select_source_price(default_currency, available_base_prices)
        return unless selected

        currency = selected.currency.to_s.upcase
        persist_currency(currency) if OriginalCurrency.table_exists?
        [selected, currency]
      end

      def self.select_source_price(default_currency, prices)
        base_currency = default_currency.to_s.upcase
        ordered = Array(prices).sort_by do |price|
          [price.created_at || Time.at(0), price.id || 0]
        end

        ordered.find { |price| price.currency.to_s.upcase == base_currency } || ordered.first
      end

      private

      # A preloaded prices association can be scoped by the API/request to only
      # the selected market currency. Use it when it contains the requested
      # source price, but query the complete base-price relation if it does not.
      def base_price_for(currency)
        association = @variant.prices
        if association.respond_to?(:loaded?) && association.loaded?
          loaded_price = source_prices(association.to_a).find do |price|
            price.currency.to_s.upcase == currency.to_s.upcase
          end
          return loaded_price if loaded_price
        end

        scope = association.base_prices.where.not(amount: nil)
        scope = scope.where(min_quantity: 1) if quantity_breaks_supported?
        source_prices([scope.find_by(currency: currency.to_s.upcase)]).first
      end

      def available_base_prices
        association = @variant.prices
        scope = association.base_prices.where.not(amount: nil)
        scope = scope.where(min_quantity: 1) if quantity_breaks_supported?
        source_prices(scope.order(:created_at, :id).to_a)
      end

      def source_prices(rows)
        rows = rows.compact.select do |price|
          price.price_list_id.nil? && price.amount.present? &&
            (!quantity_breaks_supported? || price.min_quantity.to_i == 1)
        end
        return rows unless ConvertedPrice.table_exists?

        generated_price_ids = ConvertedPrice.where(price_id: rows.map(&:id).compact).pluck(:price_id)
        rows.reject { |price| generated_price_ids.include?(price.id) }
      end

      def persist_currency(currency)
        return unless @store.persisted? && @variant.persisted?

        OriginalCurrency.create_or_find_by!(store_id: @store.id, variant_id: @variant.id) do |record|
          record.currency = currency
        end
      end

      def quantity_breaks_supported?
        defined?(Spree::Price) && Spree::Price.respond_to?(:column_names) && Spree::Price.column_names.include?("min_quantity")
      end
    end
  end
end
