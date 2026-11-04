# frozen_string_literal: true

namespace :spree do
  namespace :auto_currency_exchange do
    desc "Fetch current market rates and update eligible Spree prices now"
    task update: :environment do
      result = Spree::AutoCurrencyExchange::Refresh.new.call
      puts "Currency update complete: #{result.stores_processed} stores, #{result.rates_saved} rates, " \
           "#{result.prices_created} prices created, #{result.prices_updated} prices updated, " \
           "#{result.overrides_applied} overrides, #{result.manual_prices_preserved} manual prices preserved, " \
           "#{result.locked_prices_preserved} edited prices protected."
    end

    desc "Unlock prices edited outside the extension so the next run manages them again"
    task unlock_manual_prices: :environment do
      count = Spree::AutoCurrencyExchange::ConvertedPrice.where(locked: true).update_all(locked: false, updated_at: Time.current)
      puts "Unlocked #{count} generated price records."
    end
  end
end
