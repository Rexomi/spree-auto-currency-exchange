# frozen_string_literal: true

class CreateSpreeAutoCurrencyExchangeTables < ActiveRecord::Migration[7.2]
  def change
    create_table :spree_auto_currency_exchange_rates do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores, on_delete: :cascade }
      t.string :base_currency, null: false, limit: 3
      t.string :currency, null: false, limit: 3
      t.decimal :rate, null: false, precision: 30, scale: 12
      t.date :observed_on, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :spree_auto_currency_exchange_rates, %i[store_id base_currency currency], unique: true, name: "idx_spree_auto_exchange_rates_unique"

    create_table :spree_auto_currency_exchange_converted_prices do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores, on_delete: :cascade }
      t.references :variant, null: false, foreign_key: { to_table: :spree_variants, on_delete: :cascade }
      t.references :price, foreign_key: { to_table: :spree_prices, on_delete: :nullify }
      t.string :currency, null: false, limit: 3
      t.string :source_currency, null: false, limit: 3
      t.decimal :amount, null: false, precision: 19, scale: 4
      t.decimal :compare_at_amount, precision: 19, scale: 4
      t.decimal :source_amount, null: false, precision: 19, scale: 4
      t.decimal :source_compare_at_amount, precision: 19, scale: 4
      t.decimal :exchange_rate, null: false, precision: 30, scale: 12
      t.decimal :markup, null: false, default: 0, precision: 10, scale: 8
      t.boolean :locked, null: false, default: false
      t.datetime :last_updated_at, null: false
      t.timestamps
    end
    add_index :spree_auto_currency_exchange_converted_prices, %i[store_id variant_id currency], unique: true, name: "idx_spree_auto_exchange_prices_unique"

    create_table :spree_auto_currency_exchange_price_overrides do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores, on_delete: :cascade }
      t.references :variant, null: false, foreign_key: { to_table: :spree_variants, on_delete: :cascade }
      t.string :currency, null: false, limit: 3
      t.decimal :amount, null: false, precision: 19, scale: 4
      t.decimal :compare_at_amount, precision: 19, scale: 4
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :spree_auto_currency_exchange_price_overrides, %i[store_id variant_id currency], unique: true, name: "idx_spree_auto_exchange_overrides_unique"

    create_table :spree_auto_currency_exchange_schedules do |t|
      t.string :name, null: false
      t.datetime :next_run_at, null: false
      t.datetime :last_run_at
      t.text :last_error
      t.timestamps
    end
    add_index :spree_auto_currency_exchange_schedules, :name, unique: true, name: "idx_spree_auto_exchange_schedules_unique"
  end
end
