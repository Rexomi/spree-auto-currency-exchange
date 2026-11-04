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

  describe "daily update time" do
    it "defaults to 03:00 UTC without marking a store-local time as configured" do
      configuration = described_class.new

      expect(configuration.update_time).to eq("03:00")
      expect(configuration.update_time_configured?).to be(false)
    end

    it "reads AUTO_CURRENCY_EXCHANGE_UPDATE_TIME from the environment" do
      with_update_time_environment("04:30") do
        configuration = described_class.from_environment

        expect(configuration.update_time).to eq("04:30")
        expect(configuration.update_time_configured?).to be(true)
      end
    end

    it "rejects invalid 24-hour clock values" do
      expect { described_class.new.update_time = "25:00" }
        .to raise_error(Spree::AutoCurrencyExchange::ConfigurationError, /HH:MM/)
    end
  end

  def with_update_time_environment(value)
    key = "AUTO_CURRENCY_EXCHANGE_UPDATE_TIME"
    original = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end
end
