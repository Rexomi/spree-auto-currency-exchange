# frozen_string_literal: true

require "active_support/all"
require "bigdecimal"
require "date"
require "json"
require "net/http"
require "openssl"
require "timeout"
require "time"
require "uri"

module Spree
  module AutoCurrencyExchange
  end
end

require_relative "../lib/spree/auto_currency_exchange/errors"
require_relative "../lib/spree/auto_currency_exchange/version"
require "spree_auto_currency_exchange"
require_relative "../lib/spree/auto_currency_exchange/configuration"
require_relative "../app/services/spree/auto_currency_exchange/price_calculator"
require_relative "../app/services/spree/auto_currency_exchange/frankfurter_client"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
end
