# frozen_string_literal: true

require "spree/core"
require "active_support/all"
require "bigdecimal"
require "date"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

require_relative "auto_currency_exchange/version"
require_relative "auto_currency_exchange/configuration"
require_relative "auto_currency_exchange/errors"
require_relative "auto_currency_exchange/integrations"
require_relative "auto_currency_exchange/engine"

module Spree
  module AutoCurrencyExchange
    class << self
      def configuration
        @configuration ||= Configuration.from_environment
      end

      def configure
        yield(configuration)
      end
    end
  end
end
