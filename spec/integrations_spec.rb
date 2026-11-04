# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/spree/auto_currency_exchange/integrations"
require_relative "../app/services/spree/auto_currency_exchange/dynamic_price"

RSpec.describe Spree::AutoCurrencyExchange::Integrations do
  let(:store) { double(id: 17, default_currency: "USD") }
  let(:variant) { double(id: 23, product: double(store: store)) }

  it "uses the dynamic price resolver for storefront variant price lookups" do
    fallback = double("empty price")
    converted = double("dynamic price", amount: BigDecimal("12.00"))
    variant_class = Class.new do
      define_method(:initialize) { |product, base_price| @product, @base_price = product, base_price }
      attr_reader :product
      define_method(:price_in) { |_currency| @base_price }
    end
    variant_class.prepend(described_class::VariantPricing)
    instance = variant_class.new(variant.product, fallback)

    dynamic = instance_double(Spree::AutoCurrencyExchange::DynamicPrice)
    expect(Spree::AutoCurrencyExchange::DynamicPrice).to receive(:new)
      .with(variant: instance, currency: "EUR", store: store).and_return(dynamic)
    expect(dynamic).to receive(:resolve).with(fallback_price: fallback).and_return(converted)

    expect(instance.price_in("eur")).to equal(converted)
  end

  it "passes dynamic prices through Spree's cart pricing resolver" do
    context = double(variant: variant, currency: "EUR", store: store)
    fallback = double("base fallback")
    converted = double("dynamic price")
    resolver_class = Class.new do
      attr_reader :context
      define_method(:initialize) { |context, fallback| @context, @fallback = context, fallback }
      define_method(:find_base_price) { @fallback }
    end
    resolver_class.prepend(described_class::PricingResolver)
    resolver = resolver_class.new(context, fallback)
    dynamic = instance_double(Spree::AutoCurrencyExchange::DynamicPrice)

    expect(Spree::AutoCurrencyExchange::DynamicPrice).to receive(:new)
      .with(variant: variant, currency: "EUR", store: store).and_return(dynamic)
    expect(dynamic).to receive(:resolve).with(fallback_price: fallback).and_return(converted)

    expect(resolver.send(:find_base_price)).to equal(converted)
  end

  it "persists the converted amount and rate snapshot on a cart line item" do
    context = double
    allow(Spree::Pricing::Context).to receive(:from_order).and_return(context)
    converted = double(
      amount: BigDecimal("12.00"),
      price_list_id: nil,
      auto_currency_exchange_rate: BigDecimal("0.012"),
      auto_currency_exchange_source_currency: "INR",
      auto_currency_exchange_source_amount: BigDecimal("1000"),
      compare_at_amount: BigDecimal("14.40")
    )
    allow(converted).to receive(:price_including_vat_for).with(tax_zone: :zone).and_return(BigDecimal("12.00"))
    allow(variant).to receive(:price_for).with(context).and_return(converted)

    line_item_class = Class.new do
      prepend Spree::AutoCurrencyExchange::Integrations::LineItemPricing
      attr_accessor :price, :price_list_id, :auto_currency_exchange_rate,
                    :auto_currency_exchange_source_currency, :auto_currency_exchange_source_amount,
                    :auto_currency_exchange_compare_at_amount, :updated_at
      attr_reader :variant, :order, :quantity
      define_method(:initialize) do |variant, order|
        @variant, @order, @quantity = variant, order, 1
      end
      define_method(:tax_zone) { :zone }
      define_method(:update_columns) { |attributes| attributes.each { |key, value| public_send("#{key}=", value) } }
    end
    line_item = line_item_class.new(variant, double(completed?: false))
    line_item.price = BigDecimal("10.00")

    line_item.recalculate_price

    expect(line_item.price).to eq(BigDecimal("12.00"))
    expect(line_item.auto_currency_exchange_rate).to eq(BigDecimal("0.012"))
    expect(line_item.auto_currency_exchange_source_currency).to eq("INR")
    expect(line_item.auto_currency_exchange_source_amount).to eq(BigDecimal("1000"))
    expect(line_item.auto_currency_exchange_compare_at_amount).to eq(BigDecimal("14.40"))
  end

  it "does not recalculate an already placed order after a rate changes" do
    context = double
    allow(Spree::Pricing::Context).to receive(:from_order).and_return(context)
    order = double(completed?: true)
    line_item_class = Class.new do
      prepend Spree::AutoCurrencyExchange::Integrations::LineItemPricing
      attr_accessor :price, :price_list_id, :auto_currency_exchange_rate,
                    :auto_currency_exchange_source_currency, :auto_currency_exchange_source_amount,
                    :auto_currency_exchange_compare_at_amount
      attr_reader :variant, :order, :quantity
      define_method(:initialize) { |variant, order| @variant, @order, @quantity = variant, order, 1 }
      define_method(:tax_zone) { :zone }
      define_method(:update_columns) { raise "completed line item must not update" }
    end
    line_item = line_item_class.new(variant, order)
    line_item.price = BigDecimal("12.00")
    line_item.auto_currency_exchange_rate = BigDecimal("0.012")
    line_item.auto_currency_exchange_source_currency = "INR"
    line_item.auto_currency_exchange_source_amount = BigDecimal("1000")

    expect(variant).not_to receive(:price_for)
    line_item.recalculate_price

    expect(line_item.price).to eq(BigDecimal("12.00"))
    expect(line_item.auto_currency_exchange_rate).to eq(BigDecimal("0.012"))
  end

  it "uses the selected market currency during Spree's order currency update" do
    context = double
    allow(Spree::Pricing::Context).to receive(:from_order).and_return(context)
    converted = double(
      amount: BigDecimal("12.00"),
      price_list_id: nil,
      auto_currency_exchange_rate: BigDecimal("0.012"),
      auto_currency_exchange_source_currency: "INR",
      auto_currency_exchange_source_amount: BigDecimal("1000"),
      compare_at_amount: nil
    )
    allow(converted).to receive(:price_including_vat_for).with(tax_zone: :zone).and_return(BigDecimal("12.00"))
    allow(variant).to receive(:price_for).with(context).and_return(converted)

    line_item = double(variant: variant, quantity: 1, tax_zone: :zone)
    order_class = Class.new do
      prepend Spree::AutoCurrencyExchange::Integrations::OrderCurrencyPricing
      attr_reader :currency
      define_method(:initialize) { |currency| @currency = currency }
      define_method(:completed?) { false }
    end
    order = order_class.new("USD")
    expected_attributes = {
      currency: "USD",
      price: BigDecimal("12.00"),
      price_list_id: nil,
      auto_currency_exchange_rate: BigDecimal("0.012"),
      auto_currency_exchange_source_currency: "INR",
      auto_currency_exchange_source_amount: BigDecimal("1000"),
      auto_currency_exchange_compare_at_amount: nil
    }

    expect(line_item).to receive(:update!).with(expected_attributes)
    order.update_line_item_price!(line_item)
  end
end
