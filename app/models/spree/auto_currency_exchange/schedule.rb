# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Schedule < Spree.base_class
      self.table_name = "spree_auto_currency_exchange_schedules"

      validates :name, :next_run_at, presence: true
    end
  end
end
