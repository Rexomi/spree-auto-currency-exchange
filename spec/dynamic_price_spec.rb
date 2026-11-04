# frozen_string_literal: true

require "spec_helper"
require_relative "../app/services/spree/auto_currency_exchange/dynamic_price"
require_relative "../app/services/spree/auto_currency_exchange/original_price_resolver"
require_relative "../app/services/spree/auto_currency_exchange/rate_converter"
original_spree_base_class = Spree.base_class(constantize: false)
Spree.base_class = "ActiveRecord::Base"
require_relative "../app/models/spree/auto_currency_exchange/price_override"
require_relative "../app/models/spree/auto_currency_exchange/converted_price"
require_relative "../app/models/spree/auto_currency_exchange/rate"
Spree.base_class = original_spree_base_class

RSpec.describe Spree::AutoCurrencyExchange::DynamicPrice do
  PriceValue = Struct.new(
    :id, :variant_id, :currency, :amount, :compare_at_amount, :price_list_id,
    :min_quantity,
    :created_at, :auto_currency_exchange_rate, :auto_currency_exchange_source_currency,
    :auto_currency_exchange_source_amount, :auto_currency_exchange_manual_override,
    keyword_init: true
  )

  let(:market_relation) { double(exists?: true) }
  let(:markets) { double(where: market_relation) }
  let(:store) { Struct.new(:id, :default_currency, :markets) { def has_markets? = true }.new(17, "USD", markets) }
  let(:variant) { double(id: 23, product: double(store: store)) }

  before do
    allow(Spree::AutoCurrencyExchange::PriceOverride).to receive(:table_exists?).and_return(false)
    allow(Spree::AutoCurrencyExchange::ConvertedPrice).to receive(:table_exists?).and_return(false)
  end

  it "converts a preserved INR source price into the selected market currency from saved rates" do
    source_price = PriceValue.new(currency: "INR", amount: BigDecimal("1000"), compare_at_amount: BigDecimal("1200"))
    converter = double(call: BigDecimal("0.012"))

    converted = described_class.new(
      variant: variant,
      currency: "USD",
      store: store,
      original_price_resolver: -> { [source_price, "INR"] },
      rate_converter: converter,
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve

    expect(converted.amount).to eq(BigDecimal("12.00"))
    expect(converted.compare_at_amount).to eq(BigDecimal("14.40"))
    expect(converted.currency).to eq("USD")
    expect(converted.auto_currency_exchange_rate).to eq(BigDecimal("0.012"))
    expect(converted.auto_currency_exchange_source_currency).to eq("INR")
  end

  it "reflects a source price change without requesting another exchange rate" do
    source_price = PriceValue.new(currency: "INR", amount: BigDecimal("1000"), compare_at_amount: nil)
    converter = double(call: BigDecimal("0.01"))
    factory = ->(attributes) { PriceValue.new(**attributes) }
    resolve = lambda do
      described_class.new(
        variant: variant,
        currency: "USD",
        store: store,
        original_price_resolver: -> { [source_price, "INR"] },
        rate_converter: converter,
        price_factory: factory
      ).resolve
    end

    expect(resolve.call.amount).to eq(BigDecimal("10.00"))
    source_price.amount = BigDecimal("1500")
    expect(resolve.call.amount).to eq(BigDecimal("15.00"))
    expect(converter).to have_received(:call).twice
  end

  it "returns no converted price when the saved rate is unavailable" do
    source_price = PriceValue.new(currency: "INR", amount: BigDecimal("1000"))
    converter = double(call: nil)

    converted = described_class.new(
      variant: variant,
      currency: "USD",
      store: store,
      original_price_resolver: -> { [source_price, "INR"] },
      rate_converter: converter,
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve

    expect(converted).to be_nil
  end

  it "rounds the dynamic price using the target currency's minor-unit precision" do
    source_price = PriceValue.new(currency: "INR", amount: BigDecimal("1000"))

    converted = described_class.new(
      variant: variant,
      currency: "JPY",
      store: store,
      original_price_resolver: -> { [source_price, "INR"] },
      rate_converter: ->(**_options) { BigDecimal("0.0067") },
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve

    expect(converted.amount).to eq(BigDecimal("7"))
  end

  it "preserves a merchant-managed target-currency price" do
    merchant_price = PriceValue.new(currency: "USD", amount: BigDecimal("20"))

    converted = described_class.new(
      variant: variant,
      currency: "USD",
      store: store,
      original_price_resolver: -> { raise "source price must not be resolved" },
      rate_converter: -> { raise "rate must not be looked up" },
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve(fallback_price: merchant_price)

    expect(converted).to equal(merchant_price)
  end

  it "preserves a configured manual override without requesting a rate" do
    override = double(amount: BigDecimal("19.95"), compare_at_amount: BigDecimal("24.95"))
    allow(Spree::AutoCurrencyExchange::PriceOverride).to receive(:table_exists?).and_return(true)
    active_overrides = double
    allow(Spree::AutoCurrencyExchange::PriceOverride).to receive(:active).and_return(active_overrides)
    allow(active_overrides).to receive(:find_by).with(store_id: 17, variant_id: 23, currency: "USD").and_return(override)

    converted = described_class.new(
      variant: variant,
      currency: "USD",
      store: store,
      original_price_resolver: -> { raise "source price must not be resolved" },
      rate_converter: ->(**_options) { raise "rate must not be looked up" },
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve

    expect(converted.amount).to eq(BigDecimal("19.95"))
    expect(converted.compare_at_amount).to eq(BigDecimal("24.95"))
    expect(converted.auto_currency_exchange_manual_override).to be(true)
  end

  it "replaces an unchanged legacy generated price with dynamic conversion" do
    legacy_price = PriceValue.new(id: 91, currency: "USD", amount: BigDecimal("12.00"))
    def legacy_price.persisted? = true
    tracking = double(locked?: false, price_matches_snapshot?: true)
    allow(Spree::AutoCurrencyExchange::ConvertedPrice).to receive(:table_exists?).and_return(true)
    allow(Spree::AutoCurrencyExchange::ConvertedPrice).to receive(:find_by)
      .with(store_id: 17, variant_id: 23, currency: "USD", price_id: 91).and_return(tracking)
    source = PriceValue.new(currency: "INR", amount: BigDecimal("1000"))

    converted = described_class.new(
      variant: variant,
      currency: "USD",
      store: store,
      original_price_resolver: -> { [source, "INR"] },
      rate_converter: ->(**_options) { BigDecimal("0.012") },
      price_factory: ->(attributes) { PriceValue.new(**attributes) }
    ).resolve(fallback_price: legacy_price)

    expect(converted).not_to equal(legacy_price)
    expect(converted.amount).to eq(BigDecimal("12.00"))
    expect(converted.auto_currency_exchange_rate).to eq(BigDecimal("0.012"))
  end
end

RSpec.describe Spree::AutoCurrencyExchange::OriginalPriceResolver do
  PriceRow = Struct.new(:currency, :created_at, :id, :price_list_id, :amount, keyword_init: true)

  it "prefers the store default price even when another currency price was added first" do
    prices = [
      PriceRow.new(currency: "INR", created_at: Time.utc(2026, 1, 1), id: 1, amount: 100),
      PriceRow.new(currency: "USD", created_at: Time.utc(2026, 1, 2), id: 2, amount: 10)
    ]

    expect(described_class.select_source_price("USD", prices)).to equal(prices.last)
  end

  it "uses the first available price when the store default currency price is absent" do
    prices = [
      PriceRow.new(currency: "EUR", created_at: Time.utc(2026, 1, 2), id: 2, amount: 20),
      PriceRow.new(currency: "INR", created_at: Time.utc(2026, 1, 1), id: 1, amount: 100)
    ]

    expect(described_class.select_source_price("USD", prices)).to equal(prices.last)
  end

  it "keeps a previously selected source currency after a default-currency price is added" do
    prices = [
      PriceRow.new(currency: "INR", created_at: Time.utc(2026, 1, 1), id: 1, amount: 100),
      PriceRow.new(currency: "USD", created_at: Time.utc(2026, 1, 2), id: 2, amount: 10)
    ]
    association = double(loaded?: true, to_a: prices)
    variant = double(id: 23, prices: association)
    store = double(id: 17, default_currency: "USD")
    original_currency = double(currency: "INR")
    allow(Spree::AutoCurrencyExchange::OriginalCurrency).to receive(:table_exists?).and_return(true)
    allow(Spree::AutoCurrencyExchange::OriginalCurrency).to receive(:find_by)
      .with(store_id: 17, variant_id: 23).and_return(original_currency)
    allow(Spree::AutoCurrencyExchange::ConvertedPrice).to receive(:table_exists?).and_return(false)

    selected_price, selected_currency = described_class.new(store: store, variant: variant).call

    expect(selected_price).to equal(prices.first)
    expect(selected_currency).to eq("INR")
  end
end

RSpec.describe Spree::AutoCurrencyExchange::RateConverter do
  it "derives a cross rate from the saved store-base currency rates" do
    store = double(id: 17, default_currency: "USD")
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:table_exists?).and_return(true)
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:find_by).with(store_id: 17, base_currency: "USD", currency: "INR")
      .and_return(double(rate: BigDecimal("83.25")))
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:find_by).with(store_id: 17, base_currency: "USD", currency: "EUR")
      .and_return(double(rate: BigDecimal("0.91")))

    result = described_class.new(store: store).call(from_currency: "INR", to_currency: "EUR")

    expect(result).to be_within(BigDecimal("0.0000001")).of(BigDecimal("0.91") / BigDecimal("83.25"))
  end

  it "returns nil rather than inventing a cross rate when the source rate is missing" do
    store = double(id: 17, default_currency: "USD")
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:table_exists?).and_return(true)
    allow(Spree::AutoCurrencyExchange::Rate).to receive(:find_by).and_return(nil)

    expect(described_class.new(store: store).call(from_currency: "INR", to_currency: "EUR")).to be_nil
  end
end
