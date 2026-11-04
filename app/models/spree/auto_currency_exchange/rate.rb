# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Rate < Spree.base_class
      self.table_name = "spree_auto_currency_exchange_rates"

      belongs_to :store, class_name: "Spree::Store"

      validates :base_currency, :currency, :rate, :observed_on, :fetched_at, presence: true
      validates :rate, numericality: { greater_than: 0 }
    end
  end
end
