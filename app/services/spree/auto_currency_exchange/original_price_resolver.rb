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
        prices = available_base_prices
        return if prices.empty?

        original = if OriginalCurrency.table_exists?
                     OriginalCurrency.find_by(store_id: @store.id, variant_id: @variant.id)
                   end
        if original
          price = prices.find { |candidate| candidate.currency.to_s.upcase == original.currency }
          return [price, original.currency] if price
          return
        end

        selected = self.class.select_source_price(@store.default_currency, prices)
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

      def available_base_prices
        association = @variant.prices
        rows = if association.respond_to?(:loaded?) && association.loaded?
                 association.to_a
               else
                 scope = association.base_prices.where.not(amount: nil)
                 scope = scope.where(min_quantity: 1) if quantity_breaks_supported?
                 scope.order(:created_at, :id).to_a
               end
        rows = rows.select do |price|
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
