# frozen_string_literal: true

require "spec_helper"
require_relative "../app/services/spree/auto_currency_exchange/refresh"

RSpec.describe Spree::AutoCurrencyExchange::Refresh do
  describe "currency precision lookup" do
    it "resolves ISO currencies from the root Money namespace inside Spree" do
      refresh = described_class.new

      expect(refresh.send(:currency_precision, "NZD")).to eq(2)
      expect(refresh.send(:currency_precision, "JPY")).to eq(0)
    end
  end
end
