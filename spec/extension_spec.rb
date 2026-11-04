# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::AutoCurrencyExchange do
  it "loads as an isolated Rails engine alongside the installed Spree Core" do
    expect(Spree::AutoCurrencyExchange::Engine.superclass).to eq(Rails::Engine)
    expect(Gem.loaded_specs.fetch("spree_core").version).to be >= Gem::Version.new("5.6")
    expect(Gem.loaded_specs.fetch("spree_core").version).to be < Gem::Version.new("6.1")
  end

  it "loads all extension models, services, and jobs under a Spree-style base class" do
    original_base_class = Spree.base_class(constantize: false)

    begin
      Spree.base_class = "ActiveRecord::Base"
      Dir.glob(File.expand_path("../app/**/*.rb", __dir__)).sort.each { |path| require path }

      expect(Spree::AutoCurrencyExchange::ConvertedPrice.table_name).to eq("spree_auto_currency_exchange_converted_prices")
      expect(Spree::AutoCurrencyExchange::UpdatePricesJob.superclass).to eq(ActiveJob::Base)
    ensure
      Spree.base_class = original_base_class
    end
  end
end
