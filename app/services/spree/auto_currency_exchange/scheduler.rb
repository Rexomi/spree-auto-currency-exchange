# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Scheduler
      SCHEDULE_NAME = "daily_exchange_rate_refresh"

      class << self
        def ensure_scheduled!
          schedule = find_or_create_schedule
          timezone = timezone_for_schedule
          configuration = Spree::AutoCurrencyExchange.configuration
          run_at = schedule.with_lock do
            bootstrap_rates = initial_rate_refresh_required?
            if schedule.next_run_at.nil? || schedule.scheduled_time != configuration.update_time ||
               schedule.time_zone != timezone || (bootstrap_rates && schedule.next_run_at > Time.current)
              schedule.update!(
                scheduled_time: configuration.update_time,
                time_zone: timezone,
                next_run_at: bootstrap_rates ? Time.current : next_run_at(timezone: timezone)
              )
            end
            schedule.next_run_at
          end
          enqueue(run_at)
        end

        def run(scheduled_at)
          token = parse_time(scheduled_at)
          schedule = Schedule.find_by!(name: SCHEDULE_NAME)
          next_run_at = nil

          schedule.with_lock do
            return false unless same_time?(schedule.next_run_at, token)

            Refresh.new.call
            update_time = Spree::AutoCurrencyExchange.configuration.update_time
            timezone = timezone_for_schedule
            next_run_at = next_run_at(timezone: timezone, update_time: update_time)
            schedule.update!(
              scheduled_time: update_time,
              time_zone: timezone,
              last_run_at: Time.current,
              last_error: nil,
              next_run_at: next_run_at
            )
          end

          enqueue(next_run_at)
          true
        rescue StandardError => error
          advance_after_failure(token, error) if token
          raise
        end

        def same_time?(left, right)
          left.present? && right.present? && left.to_i == right.to_i && left.usec == right.usec
        end

        def next_run_at(after: Time.current, timezone: nil, update_time: Spree::AutoCurrencyExchange.configuration.update_time)
          timezone ||= timezone_for_schedule
          zone = ActiveSupport::TimeZone[timezone]
          raise ConfigurationError, "Unknown store timezone #{timezone.inspect}" unless zone

          hour, minute = update_time.split(":").map(&:to_i)
          local_now = after.in_time_zone(zone)
          candidate = zone.local(local_now.year, local_now.month, local_now.day, hour, minute)
          if candidate < local_now
            tomorrow = local_now.to_date + 1.day
            candidate = zone.local(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute)
          end

          candidate.utc
        end

        def timezone_for_schedule
          configuration = Spree::AutoCurrencyExchange.configuration
          store_timezone = if configuration.update_time_configured?
                            Spree::Store.find_by(default: true)&.timezone
                          end

          timezone_for(configured: configuration.update_time_configured?, store_timezone: store_timezone)
        end

        def timezone_for(configured:, store_timezone:)
          return "UTC" unless configured

          timezone = store_timezone.to_s.presence || "UTC"
          raise ConfigurationError, "Unknown store timezone #{timezone.inspect}" unless ActiveSupport::TimeZone[timezone]

          timezone
        end

        def initial_rate_refresh_required?
          return false unless defined?(Rate) && Rate.table_exists? && Spree::Store.table_exists?

          Spree::Store.find_each.any? do |store|
            base = store.default_currency.to_s.upcase
            !Rate.exists?(store_id: store.id, base_currency: base, currency: base)
          end
        end

        private

        def find_or_create_schedule
          configuration = Spree::AutoCurrencyExchange.configuration
          timezone = timezone_for_schedule
          Schedule.find_or_create_by!(name: SCHEDULE_NAME) do |record|
            record.scheduled_time = configuration.update_time
            record.time_zone = timezone
            record.next_run_at = next_run_at(timezone: timezone)
          end
        rescue ActiveRecord::RecordNotUnique
          Schedule.find_by!(name: SCHEDULE_NAME)
        end

        def advance_after_failure(token, error)
          schedule = Schedule.find_by(name: SCHEDULE_NAME)
          return unless schedule

          next_run_at = nil
          schedule.with_lock do
            return unless same_time?(schedule.next_run_at, token)

            update_time = Spree::AutoCurrencyExchange.configuration.update_time
            timezone = timezone_for_schedule
            next_run_at = next_run_at(timezone: timezone, update_time: update_time)
            schedule.update!(
              scheduled_time: update_time,
              time_zone: timezone,
              last_error: error.message.to_s.truncate(2_000),
              next_run_at: next_run_at
            )
          end
          enqueue(next_run_at) if next_run_at
        rescue StandardError => schedule_error
          Rails.logger.error("[Spree Auto Currency Exchange] Could not persist scheduler failure: #{schedule_error.message}")
        end

        def enqueue(time)
          UpdatePricesJob.set(wait_until: time).perform_later(time.iso8601(6))
        end

        def parse_time(value)
          return value.in_time_zone if value.respond_to?(:in_time_zone)

          Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
        rescue ArgumentError, TypeError
          raise ConfigurationError, "Invalid scheduled time #{value.inspect}"
        end
      end
    end
  end
end
