# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Configuration
      attr_accessor :enabled, :api_base_url, :request_timeout, :markups
      attr_reader :update_time

      def self.from_environment
        config = new
        config.enabled = ENV.fetch("AUTO_CURRENCY_EXCHANGE_ENABLED", "true").casecmp("true").zero?
        config.api_base_url = ENV.fetch("AUTO_CURRENCY_EXCHANGE_API_BASE_URL", "https://api.frankfurter.dev")
        config.request_timeout = Integer(ENV.fetch("AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT", "10"))
        config.markups = parse_markups(ENV.fetch("AUTO_CURRENCY_EXCHANGE_MARKUPS", "{}"))
        config.update_time = ENV.fetch("AUTO_CURRENCY_EXCHANGE_UPDATE_TIME") if ENV.key?("AUTO_CURRENCY_EXCHANGE_UPDATE_TIME")
        raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT must be positive" unless config.request_timeout.positive?

        config
      rescue ArgumentError
        raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT must be a whole number"
      end

      def initialize
        @enabled = true
        @api_base_url = "https://api.frankfurter.dev"
        @request_timeout = 10
        @markups = {}
        @update_time = "03:00"
        @update_time_configured = false
      end

      def update_time=(value)
        time = value.to_s
        unless time.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
          raise ConfigurationError, "AUTO_CURRENCY_EXCHANGE_UPDATE_TIME must use 24-hour HH:MM format"
        end

        @update_time = time
        @update_time_configured = true
      end

      def update_time_configured?
        @update_time_configured
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
