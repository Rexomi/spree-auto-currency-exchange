# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class PriceCalculator
      def initialize(currency:, rate:, markup: 0, precision:)
        @currency = currency.to_s.upcase
        @rate = decimal(rate, "exchange rate")
        @markup = decimal(markup, "markup")
        @precision = Integer(precision)

        raise ProviderError, "Exchange rate must be finite and greater than zero" unless @rate.finite? && @rate.positive?
        raise ConfigurationError, "Markup must be finite and greater than -100%" unless @markup.finite? && @markup > -1
        raise ConfigurationError, "Currency precision must be between 0 and 4" unless @precision.between?(0, 4)
      end

      def convert(amount)
        return nil if amount.nil?

        source = decimal(amount, "source amount")
        converted = source * @rate * (BigDecimal("1") + @markup)
        raise ProviderError, "Converted price for #{@currency} is invalid" unless converted.finite? && converted >= 0

        converted.round(@precision, BigDecimal::ROUND_HALF_UP)
      end

      private

      def decimal(value, label)
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        raise ConfigurationError, "#{label.capitalize} must be numeric"
      end
    end
  end
end
