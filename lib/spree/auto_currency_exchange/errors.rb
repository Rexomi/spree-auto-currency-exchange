# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ProviderError < Error; end
    class MissingRateError < ProviderError; end
  end
end
