# frozen_string_literal: true

class AddDynamicCurrencyPricing < ActiveRecord::Migration[7.2]
  def change
    create_table :spree_auto_currency_exchange_original_currencies do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores, on_delete: :cascade }
      t.references :variant, null: false, foreign_key: { to_table: :spree_variants, on_delete: :cascade }
      t.string :currency, null: false, limit: 3
      t.timestamps
    end
    add_index :spree_auto_currency_exchange_original_currencies, %i[store_id variant_id], unique: true,
              name: "idx_spree_auto_exchange_original_currency"

    add_column :spree_line_items, :auto_currency_exchange_rate, :decimal, precision: 30, scale: 12
    add_column :spree_line_items, :auto_currency_exchange_source_currency, :string, limit: 3
    add_column :spree_line_items, :auto_currency_exchange_source_amount, :decimal, precision: 19, scale: 4
    add_column :spree_line_items, :auto_currency_exchange_compare_at_amount, :decimal, precision: 19, scale: 4
  end
end
