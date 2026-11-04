# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Configuration
      attr_accessor :enabled, :api_base_url, :request_timeout, :markups, :interval

      def self.from_environment
        config = new
        config.enabled = ENV.fetch("AUTO_CURRENCY_EXCHANGE_ENABLED", "true").casecmp("true").zero?
        config.api_base_url = ENV.fetch("AUTO_CURRENCY_EXCHANGE_API_BASE_URL", "https://api.frankfurter.dev")
        config.request_timeout = Integer(ENV.fetch("AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT", "10"))
        config.interval = Integer(ENV.fetch("AUTO_CURRENCY_EXCHANGE_INTERVAL_HOURS", "24")).hours
        config.markups = parse_markups(ENV.fetch("AUTO_CURRENCY_EXCHANGE_MARKUPS", "{}"))
        raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT must be positive" unless config.request_timeout.positive?
        raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_INTERVAL_HOURS must be positive" unless config.interval.positive?

        config
      rescue ArgumentError
        raise ConfigurationError, "Request timeout and update interval must be whole numbers"
      end

      def initialize
        @enabled = true
        @api_base_url = "https://api.frankfurter.dev"
        @request_timeout = 10
        @interval = 24.hours
        @markups = {}
      end

      def markup_for(currency)
        value = markups.fetch(currency.to_s.upcase, 0)
        decimal = BigDecimal(value.to_s)
        raise ConfigurationError, "Markup for #{currency} must be finite and greater than -100%" unless decimal.finite? && decimal > -1

        decimal
      rescue ArgumentError
        raise ConfigurationError, "Markup for #{currency} must be a decimal fraction, such as 0.05 for 5%"
      end

      def self.parse_markups(raw)
        parsed = JSON.parse(raw)
        unless parsed.is_a?(Hash) && parsed.all? { |currency, value| currency.to_s.match?(/\A[A-Za-z]{3}\z/) && numeric?(value) }
          raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_MARKUPS must be a JSON object of three-letter currency codes and decimal fractions"
        end

        parsed.to_h do |currency, value|
          decimal = BigDecimal(value.to_s)
          unless decimal.finite? && decimal > -1
            raise ConfigurationError, "Markup for #{currency} must be finite and greater than -100%"
          end
          [currency.to_s.upcase, decimal]
        end
      rescue JSON::ParserError
        raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_MARKUPS must contain valid JSON"
      end

      def self.numeric?(value)
        BigDecimal(value.to_s).finite?
      rescue ArgumentError
        false
      end
      private_class_method :numeric?
    end
  end
end
