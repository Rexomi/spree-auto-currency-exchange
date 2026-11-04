# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class ConvertedPrice < Spree.base_class
      self.table_name = "spree_auto_currency_exchange_converted_prices"

      belongs_to :store, class_name: "Spree::Store"
      belongs_to :variant, class_name: "Spree::Variant"
      belongs_to :price, class_name: "Spree::Price", optional: true

      validates :currency, :source_currency, :amount, :source_amount, :exchange_rate, presence: true
      validates :exchange_rate, numericality: { greater_than: 0 }

      def price_matches_snapshot?(price_record)
        decimal_equal?(price_record.amount, amount) && decimal_equal?(price_record.compare_at_amount, compare_at_amount)
      end

      private

      def decimal_equal?(left, right)
        return left.nil? && right.nil? if left.nil? || right.nil?

        BigDecimal(left.to_s) == BigDecimal(right.to_s)
      end
    end
  end
end
