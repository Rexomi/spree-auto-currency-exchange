# spree-auto-currency-exchange

An independently installable Spree Commerce extension that stores a central exchange-rate snapshot and converts product prices dynamically when Spree resolves a customer's selected market currency. It reads each store's `default_currency` and configured markets at runtime. No base currency is built into the gem, and it does not create per-market converted `Spree::Price` records.

The extension uses Frankfurter's keyless API by default. It saves the complete supported rate set from each store's configured base currency in one transaction after the response has been validated. Product conversions use those saved rates; product or price changes never make an API request.

## Compatibility

The current compatibility target is:

| Component | Supported versions |
| --- | --- |
| Spree Core | 5.6.x and 6.0.x |
| Rails | 7.2.x through 8.1.x, as required by the selected Spree version |
| Ruby | 3.2+ with Spree 5.6.x; 3.3+ with Spree 6.0.x |

CI runs against Spree 5.6 and 6.0. Spree 6 quantity-break prices are supported by updating only the ordinary `min_quantity: 1` price row. This repository was supplied without a Spree application or Ruby installation, so no store-specific Spree version could be detected here.

## Installation

Add the gem to the Spree application's `Gemfile`:

```ruby
gem "spree_auto_currency_exchange", git: "https://github.com/Rexomi/spree-auto-currency-exchange"
```

Install the bundle and extension migrations:

```sh
bundle install
bin/rails railties:install:migrations
bin/rails db:migrate
```

Restart the application after the migrations. If no complete rate snapshot exists for a store's current base currency, the scheduler queues an initial refresh. The regular daily schedule then continues at its configured time.

For a RubyGems release, use `gem "spree_auto_currency_exchange", "~> 0.1"` instead.

## Configuration

Copy `.env.example` into the deployment environment or set the variables through your container platform. Frankfurter needs no API key or secret.

| Variable | Default | Purpose |
| --- | --- | --- |
| `AUTO_CURRENCY_EXCHANGE_ENABLED` | `true` | Enables the automatic daily scheduler. Set `false` to disable automatic scheduling. The manual Rake task remains available. |
| `AUTO_CURRENCY_EXCHANGE_API_BASE_URL` | `https://api.frankfurter.dev` | Frankfurter API base URL. Can point to a self-hosted compatible endpoint. |
| `AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT` | `10` | HTTP open and read timeout in seconds. |
| `AUTO_CURRENCY_EXCHANGE_UPDATE_TIME` | unset (`03:00 UTC`) | Optional daily time in 24-hour `HH:MM` format. When set, uses the default Spree store's `timezone`; if that timezone is blank, UTC is used. |
| `AUTO_CURRENCY_EXCHANGE_MARKUPS` | `{}` | JSON object mapping target market currencies to markup fractions. `0.05` means add 5%; `-0.02` means subtract 2%. |

Example:

```dotenv
AUTO_CURRENCY_EXCHANGE_MARKUPS={"EUR":0.03,"JPY":0.05}
AUTO_CURRENCY_EXCHANGE_UPDATE_TIME=04:30
```

When `AUTO_CURRENCY_EXCHANGE_UPDATE_TIME` is unset, the update runs at 03:00 UTC regardless of the app or store timezone. If the variable is set, the configured `HH:MM` is interpreted in the default Spree store's timezone. When no default store or no store timezone is available, the configured time is interpreted as UTC. Invalid times or timezone names are logged and prevent automatic scheduling until corrected.

Equivalent Ruby configuration can be placed in the app's Spree initializer:

```ruby
Spree::AutoCurrencyExchange.configure do |config|
  config.markups = { "EUR" => 0.03, "JPY" => 0.05 }
  config.update_time = "04:30"
  config.request_timeout = 15
end
```

Setting `config.update_time` also opts into the default store's timezone, using UTC when the default store has no timezone.

Markups are applied after the provider's base-to-market rate. Currency amounts are rounded to the target currency's minor unit (for example, zero decimal places for JPY).

## How pricing works

Spree's price resolver first honors applicable price lists and configured manual overrides. An explicit merchant-managed price in the selected market currency is also preserved. When no such price exists, the extension returns an in-memory `Spree::Price` calculated from the product's original price and the saved rates. It does not save that converted value to `spree_prices` or recalculate the catalog when rates change.

The source amount remains the ordinary Spree price row. On first conversion, the extension records the source currency per variant: it chooses the store's default currency when that price exists; otherwise it chooses the earliest available base price and keeps that currency for later conversions. The source amount is read from that row each time, so price edits are reflected immediately. For example, if the store base is USD but a product only has an INR price, a saved USD/INR rate and USD/target rate let Spree convert INR directly into each configured market currency without changing the store base currency.

Cross rates are derived from the same saved store-base snapshot: `(base → target) / (base → original)`. The amount and compare-at amount are rounded using the target currency's minor unit, and configured target-currency markups still apply. If either needed rate is missing, no synthetic price is returned; Spree can continue to use an explicit merchant price, otherwise the product has no price in that currency until rates are available.

Spree storefront price helpers and presenters use the dynamic `price_in` fallback. The pricing resolver used to create and recalculate cart line items uses the same conversion. Spree persists the final line-item amount and currency, and this extension additionally snapshots the source currency, source amount, and exchange rate used. Later rate refreshes update only the rate table, so existing order totals and snapshots remain unchanged.

Rates are central to the store and its current default currency. New markets and stores enqueue a rate refresh on the app's Active Job backend; changing a store's default currency queues a snapshot for the new base. Deleting a market removes only quote-currency rate rows that are no longer needed by another market or a product's original price. The daily job refreshes the full supported currency set so product source currencies do not need to be market currencies.

Earlier gem versions may have left converted Spree price rows and tracking records behind. An unchanged, unlocked tracked row is treated as legacy generated data and ignored in favor of dynamic conversion. Untracked target prices, locked rows, edited rows, and configured overrides remain merchant-managed.

### Manual overrides

Create or update an override through the extension model. The currency must be a non-base currency configured on a market for the selected store.

```ruby
store = Spree::Store.find_by!(default: true)
variant = Spree::Variant.find_by!(sku: "SKU-123")

Spree::AutoCurrencyExchange::PriceOverride.find_or_initialize_by(
  store: store,
  variant: variant,
  currency: "EUR"
).update!(amount: 29.95, compare_at_amount: 34.95)
```

An override takes priority over dynamic conversion and is returned as an in-memory Spree price. If `compare_at_amount` is omitted, no compare-at value is added. Deactivate an override with `active: false` or remove it to resume automatic conversion immediately.

The unlock task remains for compatibility with legacy converted-price tracking records:

```sh
bin/rails spree:auto_currency_exchange:unlock_manual_prices
```

## Scheduling and manual updates

The engine persists the next local run time and timezone in its schedule table. On application initialization it enqueues a delayed `UpdatePricesJob` with `perform_later`, so the application's configured Active Job adapter receives the job. If a full rate snapshot has not been saved for a store's current base currency, the first scheduled run is queued immediately to bootstrap it. After each attempt, the scheduler returns to the configured daily time. The persisted schedule token makes duplicate jobs from multiple web containers safe: only the job for the current token may run.

Keep a worker running in production and have it consume the `default` queue. For example, run `bin/jobs start` as a continuously running worker service when the app uses Solid Queue. For another adapter, run that adapter's worker process with the `default` queue enabled. The web and worker containers must share the app's queue configuration and database. Do not rely on a web process alone to execute queued work. The Rails `:async` adapter is process-local; use a durable backend for production so scheduled jobs survive restarts.

Run an update immediately from a deployment or operator shell:

```sh
bin/rails spree:auto_currency_exchange:update
```

The command fetches and validates the full rate table, saves it transactionally, and prints a summary. It does not recalculate products or change the recurring schedule.

## Docker deployment

The extension runs inside the existing Spree app; it does not require another web service or frontend. Add the gem in the app's Gemfile, rebuild the existing image, and run the extension migration as part of the release process:

```dockerfile
# The app's existing Dockerfile
RUN bundle install
```

```sh
docker compose run --rm web bin/rails railties:install:migrations
docker compose run --rm web bin/rails db:migrate
docker compose up -d --build
```

Set the configuration variables on the existing web and worker containers. Ensure the worker uses the same database and queue backend as the web process; market creation also queues a `RefreshRatesJob` on the `default` queue. For a self-hosted Frankfurter-compatible instance, set `AUTO_CURRENCY_EXCHANGE_API_BASE_URL` to its API origin and support `GET /v2/rates?base=<currency>` without a `quotes` filter so the extension can cache all supported currencies. The public Frankfurter endpoint is keyless and requires no provider credentials.

If the app's queue adapter is process-local (such as Rails `:async`), the scheduler still recovers its pending timestamp on app restart, but queued work may be lost during a restart. Use the durable queue adapter already deployed for the Spree store.

## Failure handling

- The extension validates the full rate response before opening the rate update transaction.
- Provider timeouts, HTTP errors, malformed responses, non-positive rates, and database errors abort the refresh.
- A failed refresh leaves Spree prices and the last successful rate snapshot unchanged. The scheduled job records the failed attempt and schedules the next daily attempt.
- Rate rows commit in one transaction. Validation or database failures roll back the new snapshot.
- No product price is inferred from a previously converted currency price. Dynamic conversion starts from the variant's recorded original-currency price row.
- If the provider has no saved rate for a source or target currency, the extension returns no synthetic price for that conversion. Retain a manual target price or use a provider with coverage for those currencies.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No scheduled update | Confirm both migrations ran, automatic scheduling is enabled, `AUTO_CURRENCY_EXCHANGE_UPDATE_TIME` is valid, and an Active Job worker is running for the `default` queue. Restart the app after migrating or changing scheduling configuration. |
| HTTP or missing-rate error | Check API reachability and the store/market currency codes. Frankfurter provides `/v2/currencies` for available codes. Existing prices remain unchanged on failure. |
| A product has no price in a market | Check that the product has an original Spree price, the market exists, and rates for both the original and target currencies are saved for the store's current base currency. Missing rates intentionally produce no synthetic price. |
| Prices do not appear to change | An explicit target-currency price, price-list entry, configured override, or legacy manually edited/locked row takes precedence over conversion. |
| Wrong base currency | Check `Spree::Store#default_currency`. The extension does not read a hardcoded currency or Rails locale as its source. |
| Scheduler is disabled in a container | Check `AUTO_CURRENCY_EXCHANGE_ENABLED`, queue backend configuration, and that a worker process is present. |
| Rates do not support a configured currency | Frankfurter's blended endpoint covers many active currencies but not every possible currency code. Use a compatible provider endpoint with coverage or retain a manual override. |

## Development

```sh
bundle install
bundle exec rake spec
gem build spree_auto_currency_exchange.gemspec
```

The test suite covers engine loading, rate snapshot storage, market-rate lifecycle, source-currency fallback, cross-rate math, dynamic storefront resolution, cart and order snapshots, markup and minor-unit rounding, and provider failures. GitHub Actions runs it across the supported Spree and Rails combinations.

## License

GNU AGPL-3.0-or-later. See [LICENSE](LICENSE).
