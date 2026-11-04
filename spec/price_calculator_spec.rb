# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::AutoCurrencyExchange::PriceCalculator do
  it "converts from the supplied base-currency rate and applies a currency markup" do
    calculator = described_class.new(currency: "EUR", rate: "0.92", markup: "0.05", precision: 2)

    expect(calculator.convert("100.00")).to eq(BigDecimal("96.60"))
  end

  it "rounds to the target currency minor-unit precision" do
    calculator = described_class.new(currency: "JPY", rate: "1.23456", precision: 0)

    expect(calculator.convert("10")).to eq(BigDecimal("12"))
  end

  it "keeps compare-at prices optional" do
    calculator = described_class.new(currency: "EUR", rate: "0.92", precision: 2)

    expect(calculator.convert(nil)).to be_nil
  end

  it "rejects invalid and non-finite rates" do
    expect do
      described_class.new(currency: "EUR", rate: "0", precision: 2)
    end.to raise_error(Spree::AutoCurrencyExchange::ProviderError)

    expect do
      described_class.new(currency: "EUR", rate: "NaN", precision: 2)
    end.to raise_error(Spree::AutoCurrencyExchange::ProviderError)
  end

  it "rejects markups at or below negative one hundred percent" do
    expect do
      described_class.new(currency: "EUR", rate: "1", markup: "-1", precision: 2)
    end.to raise_error(Spree::AutoCurrencyExchange::ConfigurationError)
  end
end
