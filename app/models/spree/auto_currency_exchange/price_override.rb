# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class PriceOverride < Spree.base_class
      self.table_name = "spree_auto_currency_exchange_price_overrides"

      belongs_to :store, class_name: "Spree::Store"
      belongs_to :variant, class_name: "Spree::Variant"

      before_validation :normalize_currency

      validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
      validates :amount, numericality: { greater_than_or_equal_to: 0 }
      validates :compare_at_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validate :currency_must_be_a_non_base_market_currency
      validate :variant_must_belong_to_store

      scope :active, -> { where(active: true) }

      private

      def normalize_currency
        self.currency = currency.to_s.upcase if currency.present?
      end

      def currency_must_be_a_non_base_market_currency
        return if store.blank? || currency.blank?

        if currency == store.default_currency.to_s.upcase
          errors.add(:currency, "cannot override the store's base currency")
        elsif !store.markets.where(currency: currency).exists?
          errors.add(:currency, "must be configured on a market for this store")
        end
      end

      def variant_must_belong_to_store
        return if store.blank? || variant.blank?
        return if variant.product.store_id == store.id

        errors.add(:variant, "must belong to the selected store")
      end
    end
  end
end
