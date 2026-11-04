# spree-auto-currency-exchange

An independently installable Spree Commerce extension that refreshes public reference rates once a day and writes converted prices into Spree's own `Spree::Price` records. It reads each store's `default_currency` and each configured market's `currency` at runtime. No base currency is built into the gem.

The extension uses the Frankfurter API by default. Its public endpoint is keyless and publishes daily reference rates from central banks and other official sources. The extension requests every target market currency from the store's configured base currency and updates prices in one database transaction only after the full rate set has been received and validated.

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

Restart the application after the migrations. The engine will enqueue an initial background refresh and persist the next run time.

For a RubyGems release, use `gem "spree_auto_currency_exchange", "~> 0.1"` instead.

## Configuration

Copy `.env.example` into the deployment environment or set the variables through your container platform. Frankfurter needs no API key or secret.

| Variable | Default | Purpose |
| --- | --- | --- |
| `AUTO_CURRENCY_EXCHANGE_ENABLED` | `true` | Enables the automatic daily scheduler. Set `false` to disable automatic scheduling. The manual Rake task remains available. |
| `AUTO_CURRENCY_EXCHANGE_API_BASE_URL` | `https://api.frankfurter.dev` | Frankfurter API base URL. Can point to a self-hosted compatible endpoint. |
| `AUTO_CURRENCY_EXCHANGE_REQUEST_TIMEOUT` | `10` | HTTP open and read timeout in seconds. |
| `AUTO_CURRENCY_EXCHANGE_INTERVAL_HOURS` | `24` | Delay after each attempt before the next scheduled attempt. |
| `AUTO_CURRENCY_EXCHANGE_MARKUPS` | `{}` | JSON object mapping target market currencies to markup fractions. `0.05` means add 5%; `-0.02` means subtract 2%. |

Example:

```dotenv
AUTO_CURRENCY_EXCHANGE_MARKUPS={"EUR":0.03,"JPY":0.05}
```

Equivalent Ruby configuration can be placed in the app's Spree initializer:

```ruby
Spree::AutoCurrencyExchange.configure do |config|
  config.markups = { "EUR" => 0.03, "JPY" => 0.05 }
  config.request_timeout = 15
end
```

Markups are applied after the provider's base-to-market rate. Currency amounts are rounded to the target currency's minor unit (for example, zero decimal places for JPY).

## How pricing works

For each store, the extension reads `Spree::Store#default_currency` as the source currency and the distinct currencies on that store's active `Spree::Market` records as targets. It reads the source amount from each variant's ordinary Spree price row, then creates or updates the target currency's ordinary `Spree::Price` row. Spree's storefront, cart, and checkout price resolution therefore uses the persisted target currency prices without a storefront or core patch.

The source/base currency price is never modified. Existing price-list rows are never changed. Existing target currency prices without an extension tracking row are treated as merchant-managed and preserved. If a merchant edits an extension-managed target price directly, the extension detects the amount mismatch and locks that row from future automated updates.

Generated values are always recalculated from the current source price and the latest rate, so daily refreshes do not compound rounding or markup. Compare-at prices are converted alongside regular prices. If the store's default currency changes, the newly configured source currency is read on the next run; its existing price becomes the source and is left untouched.

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

An override takes priority over the computed amount while remaining a real Spree price row. If `compare_at_amount` is omitted, the source compare-at amount is converted normally. Deactivate an override with `active: false` or remove it to resume automatic conversion on the next refresh.

To allow automated management again for prices manually changed directly in Spree Admin or another integration, run:

```sh
bin/rails spree:auto_currency_exchange:unlock_manual_prices
```

## Scheduling and manual updates

The engine uses Active Job and the application's configured queue adapter. It persists the next run in the extension table, enqueues the first update on application initialization, and schedules the next attempt 24 hours after each attempt. The persisted schedule token makes duplicate jobs from multiple web containers safe: only the job for the current token may run. Use a durable queue backend and keep at least one worker running in production.

Run an update immediately from a deployment or operator shell:

```sh
bin/rails spree:auto_currency_exchange:update
```

The command fetches and validates rates, updates prices transactionally, and prints a summary. It does not change the recurring schedule.

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

Set the configuration variables on the existing web and worker containers. Ensure the worker uses the same database and queue backend as the web process. For a self-hosted Frankfurter instance, set `AUTO_CURRENCY_EXCHANGE_API_BASE_URL` to its API origin. Frankfurter documents its own Docker deployment and does not require the extension to ship provider credentials.

If the app's queue adapter is process-local (such as Rails `:async`), the scheduler still recovers its pending timestamp on app restart, but queued work may be lost during a restart. Use the durable queue adapter already deployed for the Spree store.

## Failure handling

- The extension validates the full requested rate set before opening the price update transaction.
- Provider timeouts, HTTP errors, malformed responses, non-positive rates, missing currencies, and calculation errors abort the refresh.
- A failed refresh leaves Spree prices and the saved successful rate snapshot unchanged. It records the failed attempt and schedules the next daily attempt.
- Price writes and rate snapshots commit in one transaction. Validation or database failures roll them back together.
- No product price is inferred from a previously converted currency price; every conversion starts from the store's current base-currency row.
- Unsupported currencies are reported as provider errors and require either provider coverage or a merchant override.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No scheduled update | Confirm the migration ran, automatic scheduling is enabled, and an Active Job worker is running. Restart the app after migrating. |
| HTTP or missing-rate error | Check API reachability and the store/market currency codes. Frankfurter provides `/v2/currencies` for available codes. Existing prices remain unchanged on failure. |
| Prices do not change | The target currency may be the base currency, have an active manual override, have an untracked merchant-managed price, or have a manually edited row marked locked. Inspect `Spree::AutoCurrencyExchange::ConvertedPrice` and `PriceOverride`. |
| Wrong base currency | Check `Spree::Store#default_currency`. The extension does not read a hardcoded currency or Rails locale as its source. |
| Scheduler is disabled in a container | Check `AUTO_CURRENCY_EXCHANGE_ENABLED`, queue backend configuration, and that a worker process is present. |
| Rates do not support a configured currency | Frankfurter's blended endpoint covers many active currencies but not every possible currency code. Use a compatible provider endpoint with coverage or retain a manual override. |

## Development

```sh
bundle install
bundle exec rake spec
gem build spree_auto_currency_exchange.gemspec
```

The test suite covers engine loading, extension model and job loading, conversion math, markup validation, minor-unit rounding, and rejection of failed or incomplete provider responses. GitHub Actions runs it across the supported Spree and Rails combinations.

## License

GNU AGPL-3.0-or-later. See [LICENSE](LICENSE).
