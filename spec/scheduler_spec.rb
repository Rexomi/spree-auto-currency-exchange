# frozen_string_literal: true

require "spec_helper"
require_relative "../app/services/spree/auto_currency_exchange/scheduler"

RSpec.describe Spree::AutoCurrencyExchange::Scheduler do
  describe ".timezone_for" do
    it "defaults to UTC when no time was configured, even if the store has a timezone" do
      expect(described_class.timezone_for(configured: false, store_timezone: "Asia/Kolkata")).to eq("UTC")
    end

    it "uses the store timezone for an explicitly configured time" do
      expect(described_class.timezone_for(configured: true, store_timezone: "America/New_York")).to eq("America/New_York")
    end

    it "uses UTC when the store has no timezone" do
      expect(described_class.timezone_for(configured: true, store_timezone: nil)).to eq("UTC")
    end

    it "rejects an invalid configured timezone" do
      expect do
        described_class.timezone_for(configured: true, store_timezone: "Mars/Olympus")
      end.to raise_error(Spree::AutoCurrencyExchange::ConfigurationError, /timezone/)
    end
  end

  describe ".next_run_at" do
    it "returns the next configured wall-clock time in the requested timezone" do
      run_at = described_class.next_run_at(
        after: Time.utc(2026, 11, 5, 7, 15),
        timezone: "America/New_York",
        update_time: "03:00"
      )

      expect(run_at).to eq(Time.utc(2026, 11, 5, 8, 0))
    end

    it "moves to the next day when today's update time has passed" do
      run_at = described_class.next_run_at(
        after: Time.utc(2026, 11, 5, 9, 0),
        timezone: "America/New_York",
        update_time: "03:00"
      )

      expect(run_at).to eq(Time.utc(2026, 11, 6, 8, 0))
    end
  end
end
