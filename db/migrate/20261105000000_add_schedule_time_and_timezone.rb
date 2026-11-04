# frozen_string_literal: true

class AddScheduleTimeAndTimezone < ActiveRecord::Migration[7.2]
  def change
    add_column :spree_auto_currency_exchange_schedules, :scheduled_time, :string
    add_column :spree_auto_currency_exchange_schedules, :time_zone, :string
  end
end
