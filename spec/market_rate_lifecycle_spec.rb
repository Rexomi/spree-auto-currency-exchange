# frozen_string_literal: true

require "spec_helper"
require_relative "../app/services/spree/auto_currency_exchange/market_rate_lifecycle"
require_relative "../app/jobs/spree/auto_currency_exchange/refresh_rates_job"
original_spree_base_class = Spree.base_class(constantize: false)
Spree.base_class = "ActiveRecord::Base"
require_relative "../app/models/spree/auto_currency_exchange/rate"
require_relative "../app/models/spree/auto_currency_exchange/original_currency"
Spree.base_class = original_spree_base_class

RSpec.describe Spree::AutoCurrencyExchange::MarketRateLifecycle do
  let(:configuration) { double(enabled: true) }

  before do
    allow(Spree::AutoCurrencyExchange).to receive(:configuration).and_return(configuration)
  end

  it "queues a saved-rate refresh after a market is created" do
    market = double(store_id: 17)
    expect(Spree::AutoCurrencyExchange::RefreshRatesJob).to receive(:perform_later).with(17)

    described_class.refresh_later(market)
    expect(Spree::AutoCurrencyExchange::RefreshRatesJob.queue_name).to eq("default")
  end

  it "queues a refresh when a store is created or changes its default currency" do
    store = double(id: 17)
    expect(Spree::AutoCurrencyExchange::RefreshRatesJob).to receive(:perform_later).with(17)

    described_class.refresh_later(store)
  end

  it "connects store creation and default-currency changes to the rate refresh job" do
    store_class = Class.new(ActiveRecord::Base) do
      self.abstract_class = true
      include Spree::AutoCurrencyExchange::Integrations::StoreCallbacks
    end
    store = store_class.allocate

    expect(Spree::AutoCurrencyExchange::MarketRateLifecycle).to receive(:refresh_later).with(store)
    store.send(:refresh_auto_currency_exchange_rates)
    expect(store_class._commit_callbacks.map(&:filter)).to include(:refresh_auto_currency_exchange_rates)
  end

  it "removes only an unused quote currency when its market is deleted" do
    markets = double(where: double(exists?: false))
    store = double(markets: markets)
    store_model = Class.new
    stub_const("Spree::Store", store_model)
    allow(store_model).to receive(:find_by).with(id: 17).and_return(store)
    allow(Spree::AutoCurrencyExchange::OriginalCurrency).to receive(:table_exists?).and_return(false)
    allow(described_class).to receive(:source_price_exists?).with(17, "EUR").and_return(false)

    rates = double
    cleanup = double(delete_all: 1)
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:where).with(store_id: 17, currency: "EUR").and_return(rates)
    allow(rates).to receive(:where).with(no_args).and_return(rates)
    allow(rates).to receive(:not).with(base_currency: "EUR").and_return(cleanup)

    expect(cleanup).to receive(:delete_all).once
    described_class.remove_unused_currency_rates(store_id: 17, currency: "eur")
  end

  it "keeps shared-market exchange rates when another market uses that currency" do
    markets = double(where: double(exists?: true))
    store_model = Class.new
    stub_const("Spree::Store", store_model)
    allow(store_model).to receive(:find_by).with(id: 17).and_return(double(markets: markets))
    expect(Spree::AutoCurrencyExchange::Rate).not_to receive(:where)

    described_class.remove_unused_currency_rates(store_id: 17, currency: "EUR")
  end

  it "keeps rates when the currency is still used as a product source currency" do
    markets = double(where: double(exists?: false))
    store_model = Class.new
    stub_const("Spree::Store", store_model)
    allow(store_model).to receive(:find_by).with(id: 17).and_return(double(markets: markets))
    allow(Spree::AutoCurrencyExchange::OriginalCurrency).to receive(:table_exists?).and_return(true)
    allow(Spree::AutoCurrencyExchange::OriginalCurrency).to receive(:where).with(store_id: 17, currency: "INR")
      .and_return(double(exists?: true))
    expect(Spree::AutoCurrencyExchange::Rate).not_to receive(:where)

    described_class.remove_unused_currency_rates(store_id: 17, currency: "INR")
  end
end
