# frozen_string_literal: true

require "spec_helper"
require_relative "../app/services/spree/auto_currency_exchange/refresh"
original_spree_base_class = Spree.base_class(constantize: false)
Spree.base_class = "ActiveRecord::Base"
require_relative "../app/models/spree/auto_currency_exchange/rate"
Spree.base_class = original_spree_base_class

RSpec.describe Spree::AutoCurrencyExchange::Refresh do
  it "saves the central all-currency snapshot without recalculating product prices" do
    store = Struct.new(:id, :default_currency).new(17, "USD")
    store_scope = [store]
    allow(store_scope).to receive(:find_each).and_return(store_scope)
    store_model = Class.new
    allow(store_model).to receive(:all).and_return(store_scope)
    allow(store_model).to receive(:lock).and_return(double(find: store))
    stub_const("Spree::Store", store_model)

    rate_set = Spree::AutoCurrencyExchange::FrankfurterClient::RateSet.new(
      base_currency: "USD",
      rates: { "EUR" => BigDecimal("0.91"), "INR" => BigDecimal("83.25") },
      observed_on: Date.new(2026, 11, 4),
      fetched_at: Time.utc(2026, 11, 5)
    )
    client = instance_double(Spree::AutoCurrencyExchange::FrankfurterClient, fetch_all: rate_set)

    rate_scope = double
    snapshot_cleanup = double
    base_cleanup = double
    old_base_scope = double
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:where).with(store_id: 17, base_currency: "USD").and_return(rate_scope)
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:where).with(store_id: 17).and_return(old_base_scope)
    allow(rate_scope).to receive(:where).and_return(snapshot_cleanup)
    allow(snapshot_cleanup).to receive(:not).with(currency: %w[EUR INR USD]).and_return(snapshot_cleanup)
    allow(snapshot_cleanup).to receive(:delete_all).and_return(0)
    allow(old_base_scope).to receive(:where).and_return(base_cleanup)
    allow(base_cleanup).to receive(:not).with(base_currency: "USD").and_return(base_cleanup)
    allow(base_cleanup).to receive(:delete_all).and_return(0)
    allow(ActiveRecord::Base).to receive(:transaction).and_yield

    expect(client).to receive(:fetch_all).with(base_currency: "USD")
    expect(Spree::AutoCurrencyExchange::Rate).to receive(:upsert_all) do |rows, unique_by:|
      expect(unique_by).to eq("idx_spree_auto_exchange_rates_unique")
      expect(rows.map { |row| row[:currency] }).to contain_exactly("EUR", "INR", "USD")
      expect(rows.find { |row| row[:currency] == "USD" }[:rate]).to eq(BigDecimal("1"))
    end
    expect(base_cleanup).to receive(:delete_all).once
    result = described_class.new(client: client).call

    expect(result.stores_processed).to eq(1)
    expect(result.rates_saved).to eq(3)
  end

  it "leaves the previously saved snapshot untouched when fetching rates fails" do
    store = Struct.new(:id, :default_currency).new(17, "USD")
    store_scope = [store]
    allow(store_scope).to receive(:find_each).and_return(store_scope)
    stub_const("Spree::Store", Class.new { define_singleton_method(:all) { store_scope } })
    client = instance_double(Spree::AutoCurrencyExchange::FrankfurterClient)
    allow(client).to receive(:fetch_all).and_raise(Spree::AutoCurrencyExchange::ProviderError, "provider unavailable")

    expect(ActiveRecord::Base).not_to receive(:transaction)
    expect(Spree::AutoCurrencyExchange::Rate).not_to receive(:upsert_all)

    expect { described_class.new(client: client).call }.to raise_error(Spree::AutoCurrencyExchange::ProviderError, "provider unavailable")
  end

  it "does not save a snapshot fetched for a base currency that changed before commit" do
    original_store = Struct.new(:id, :default_currency).new(17, "USD")
    current_store = Struct.new(:id, :default_currency).new(17, "INR")
    store_scope = [original_store]
    allow(store_scope).to receive(:find_each).and_return(store_scope)
    store_model = Class.new
    allow(store_model).to receive(:all).and_return(store_scope)
    allow(store_model).to receive(:lock).and_return(double(find: current_store))
    stub_const("Spree::Store", store_model)
    rate_set = Spree::AutoCurrencyExchange::FrankfurterClient::RateSet.new(
      base_currency: "USD",
      rates: { "EUR" => BigDecimal("0.91") },
      observed_on: Date.new(2026, 11, 4),
      fetched_at: Time.utc(2026, 11, 5)
    )
    client = instance_double(Spree::AutoCurrencyExchange::FrankfurterClient, fetch_all: rate_set)
    allow(ActiveRecord::Base).to receive(:transaction).and_yield

    expect(Spree::AutoCurrencyExchange::Rate).not_to receive(:upsert_all)
    result = described_class.new(client: client).call

    expect(result.stores_processed).to eq(0)
    expect(result.rates_saved).to eq(0)
  end
end
