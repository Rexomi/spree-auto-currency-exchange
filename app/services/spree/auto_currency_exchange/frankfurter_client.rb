# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class FrankfurterClient
      RateSet = Struct.new(:base_currency, :rates, :observed_on, :fetched_at, keyword_init: true)
      MAX_RESPONSE_BYTES = 1_048_576

      def initialize(configuration: Spree::AutoCurrencyExchange.configuration, http: Net::HTTP)
        @configuration = configuration
        @http = http
      end

      def fetch(base_currency:, currencies:)
        base = normalize_currency(base_currency)
        quotes = Array(currencies).map { |currency| normalize_currency(currency) }.uniq - [base]
        return RateSet.new(base_currency: base, rates: {}, observed_on: Date.current, fetched_at: Time.current) if quotes.empty?

        uri = rates_uri(base, quotes)
        response = @http.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @configuration.request_timeout,
          read_timeout: @configuration.request_timeout
        ) do |connection|
          connection.get(uri.request_uri, "Accept" => "application/json", "User-Agent" => "spree-auto-currency-exchange/#{VERSION}")
        end

        unless response.code.to_i.between?(200, 299)
          raise ProviderError, "Frankfurter returned HTTP #{response.code}"
        end
        raise ProviderError, "Frankfurter response exceeded #{MAX_RESPONSE_BYTES} bytes" if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

        parse_response(response.body, expected_base: base, expected_quotes: quotes)
      rescue ProviderError
        raise
      rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, URI::InvalidURIError, JSON::ParserError => error
        raise ProviderError, "Unable to fetch exchange rates from Frankfurter: #{error.message}"
      end

      private

      def rates_uri(base, quotes)
        base_uri = URI.parse(@configuration.api_base_url)
        raise ConfigurationError, "Exchange-rate API URL must use HTTP or HTTPS" unless %w[http https].include?(base_uri.scheme)
        raise ConfigurationError, "Exchange-rate API URL must include a host" if base_uri.host.blank?

        prefix = base_uri.path.to_s.sub(%r{/+\z}, "")
        base_uri.path = "#{prefix}/v2/rates"
        base_uri.query = URI.encode_www_form(base: base, quotes: quotes.join(","))
        base_uri.fragment = nil
        base_uri
      rescue URI::InvalidURIError => error
        raise ConfigurationError, "Invalid exchange-rate API URL: #{error.message}"
      end

      def parse_response(body, expected_base:, expected_quotes:)
        rows = JSON.parse(body)
        raise ProviderError, "Frankfurter returned an unexpected response format" unless rows.is_a?(Array)

        rates = {}
        observations = []
        rows.each do |row|
          next unless row.is_a?(Hash)

          base = normalize_currency(row["base"])
          quote = normalize_currency(row["quote"])
          next unless base == expected_base && expected_quotes.include?(quote)

          rate = BigDecimal(row.fetch("rate").to_s)
          raise ProviderError, "Frankfurter returned an invalid rate for #{quote}" unless rate.finite? && rate.positive?

          rates[quote] = rate
          observations << Date.iso8601(row.fetch("date").to_s)
        end

        missing = expected_quotes - rates.keys
        raise MissingRateError, "Frankfurter has no rate for #{missing.join(', ')} from #{expected_base}" if missing.any?

        RateSet.new(base_currency: expected_base, rates: rates, observed_on: observations.min, fetched_at: Time.current)
      rescue KeyError, ArgumentError, TypeError => error
        raise ProviderError, "Frankfurter returned malformed rate data: #{error.message}"
      end

      def normalize_currency(currency)
        value = currency.to_s.upcase
        raise ConfigurationError, "Currency codes must be three letters: #{currency.inspect}" unless value.match?(/\A[A-Z]{3}\z/)

        value
      end
    end
  end
end
