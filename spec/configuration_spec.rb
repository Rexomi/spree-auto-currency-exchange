# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::AutoCurrencyExchange::Configuration do
  describe ".parse_markups" do
    it "normalizes currency codes and parses decimal fractions" do
      expect(described_class.parse_markups('{"eur":0.025}')).to eq("EUR" => BigDecimal("0.025"))
    end

    it "requires a JSON object with three-letter currency codes" do
      expect { described_class.parse_markups("[]") }.to raise_error(Spree::AutoCurrencyExchange::ConfigurationError)
      expect { described_class.parse_markups('{"EURO":0.1}') }.to raise_error(Spree::AutoCurrencyExchange::ConfigurationError)
    end
  end
end
