# frozen_string_literal: true

namespace :spree do
  namespace :auto_currency_exchange do
    desc "Fetch the current exchange-rate table now"
    task update: :environment do
      result = Spree::AutoCurrencyExchange::Refresh.new.call
      puts "Exchange-rate update complete: #{result.stores_processed} stores, #{result.rates_saved} rates saved."
    end

    desc "Unlock prices edited outside the extension so the next run manages them again"
    task unlock_manual_prices: :environment do
      count = Spree::AutoCurrencyExchange::ConvertedPrice.where(locked: true).update_all(locked: false, updated_at: Time.current)
      puts "Unlocked #{count} generated price records."
    end
  end
end
