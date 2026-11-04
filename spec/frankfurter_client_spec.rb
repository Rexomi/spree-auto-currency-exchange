# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::AutoCurrencyExchange::FrankfurterClient do
  let(:configuration) do
    Spree::AutoCurrencyExchange::Configuration.new.tap do |config|
      config.api_base_url = "https://rates.example.test"
      config.request_timeout = 3
    end
  end

  let(:response) do
    Struct.new(:code, :body).new("200", [
      { date: "2026-11-04", base: "USD", quote: "EUR", rate: 0.92 },
      { date: "2026-11-04", base: "USD", quote: "JPY", rate: 150.25 }
    ].to_json)
  end

  let(:http) do
    Class.new do
      define_method(:initialize) { |result| @result = result }
      define_method(:start) do |_host, _port, **_options, &block|
        connection = Object.new
        connection.instance_variable_set(:@result, @result)
        connection.define_singleton_method(:get) { |_request_uri, _headers| @result }
        block.call(connection)
      end
    end.new(response)
  end

  it "requests rates from the provided base currency and validates all requested quotes" do
    client = described_class.new(configuration: configuration, http: http)
    result = client.fetch(base_currency: "usd", currencies: %w[EUR JPY])

    expect(result.base_currency).to eq("USD")
    expect(result.rates).to eq("EUR" => BigDecimal("0.92"), "JPY" => BigDecimal("150.25"))
  end

  it "fails closed when the provider does not return every requested currency" do
    response.body = [{ date: "2026-11-04", base: "USD", quote: "EUR", rate: 0.92 }].to_json
    client = described_class.new(configuration: configuration, http: http)

    expect do
      client.fetch(base_currency: "USD", currencies: %w[EUR JPY])
    end.to raise_error(Spree::AutoCurrencyExchange::MissingRateError, /JPY/)
  end

  it "does not accept failed provider responses" do
    response.code = "503"
    client = described_class.new(configuration: configuration, http: http)

    expect do
      client.fetch(base_currency: "USD", currencies: ["EUR"])
    end.to raise_error(Spree::AutoCurrencyExchange::ProviderError, /HTTP 503/)
  end
end
