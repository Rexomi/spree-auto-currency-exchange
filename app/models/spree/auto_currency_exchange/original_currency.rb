# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class OriginalCurrency < Spree.base_class
      self.table_name = "spree_auto_currency_exchange_original_currencies"

      belongs_to :store, class_name: "Spree::Store"
      belongs_to :variant, class_name: "Spree::Variant"

      validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
      validates :variant_id, uniqueness: { scope: :store_id }
    end
  end
end
