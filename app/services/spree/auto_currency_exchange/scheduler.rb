# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    class Scheduler
      SCHEDULE_NAME = "daily_exchange_rate_refresh"

      class << self
        def ensure_scheduled!
          schedule = find_or_create_schedule
          schedule.with_lock do
            schedule.update!(next_run_at: Time.current) if schedule.next_run_at.nil?
          end
          enqueue(schedule.next_run_at)
        end

        def run(scheduled_at)
          token = parse_time(scheduled_at)
          schedule = Schedule.find_by!(name: SCHEDULE_NAME)
          next_run_at = nil

          schedule.with_lock do
            return false unless same_time?(schedule.next_run_at, token)

            Refresh.new.call
            next_run_at = Time.current + Spree::AutoCurrencyExchange.configuration.interval
            schedule.update!(last_run_at: Time.current, last_error: nil, next_run_at: next_run_at)
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

        private

        def find_or_create_schedule
          Schedule.find_or_create_by!(name: SCHEDULE_NAME) do |record|
            record.next_run_at = Time.current
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

            next_run_at = Time.current + Spree::AutoCurrencyExchange.configuration.interval
            schedule.update!(last_error: error.message.to_s.truncate(2_000), next_run_at: next_run_at)
          end
          enqueue(next_run_at) if next_run_at
        rescue ActiveRecord::ActiveRecordError => schedule_error
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
