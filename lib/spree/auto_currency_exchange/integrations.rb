# frozen_string_literal: true

module Spree
  module AutoCurrencyExchange
    module Integrations
      module PriceSnapshotAttributes
        attr_accessor :auto_currency_exchange_rate,
                      :auto_currency_exchange_source_currency,
                      :auto_currency_exchange_source_amount,
                      :auto_currency_exchange_manual_override
      end

      module MarketCallbacks
        extend ActiveSupport::Concern

        included do
          after_commit :refresh_auto_currency_exchange_rates, on: :create
          after_commit :refresh_auto_currency_exchange_rates, on: :update, if: :saved_change_to_currency?
          after_commit :remove_previous_auto_currency_exchange_rates, on: :update, if: :saved_change_to_currency?
          after_destroy_commit :remove_auto_currency_exchange_rates
        end

        private

        def refresh_auto_currency_exchange_rates
          MarketRateLifecycle.refresh_later(self)
        end

        def remove_previous_auto_currency_exchange_rates
          previous_currency = saved_change_to_currency&.first
          MarketRateLifecycle.remove_unused_currency_rates(store_id: store_id, currency: previous_currency) if previous_currency
        end

        def remove_auto_currency_exchange_rates
          MarketRateLifecycle.remove_unused_currency_rates(store_id: store_id, currency: currency)
        end
      end

      module StoreCallbacks
        extend ActiveSupport::Concern

        included do
          after_commit :refresh_auto_currency_exchange_rates, on: :create
          after_commit :refresh_auto_currency_exchange_rates, on: :update, if: :saved_change_to_default_currency?
        end

        private

        def refresh_auto_currency_exchange_rates
          MarketRateLifecycle.refresh_later(self)
        end
      end

      module VariantPricing
        def price_in(currency)
          requested_currency = currency&.upcase
          existing_price = super(requested_currency)
          dynamic_price = DynamicPrice.new(
            variant: self,
            currency: requested_currency,
            store: product&.store
          ).resolve(fallback_price: existing_price)

          dynamic_price || existing_price
        end

        # Spree's Store API serializers resolve the displayed price through
        # Variant#price_for. In Spree 6, that path moved from
        # Spree::Pricing::Resolver to the configured PricingProvider, so a
        # resolver-only prepend does not cover API product pages. Wrap the
        # public entry point as well; explicit price-list and merchant prices
        # remain intact because DynamicPrice preserves populated fallbacks.
        def price_for(context_or_options)
          existing_price = super
          dynamic_price = DynamicPrice.new(
            variant: self,
            currency: auto_currency_exchange_context_value(context_or_options, :currency),
            store: auto_currency_exchange_context_value(context_or_options, :store)
          ).resolve(fallback_price: existing_price)

          dynamic_price || existing_price
        end

        private

        def auto_currency_exchange_context_value(context_or_options, key)
          return context_or_options.public_send(key) if context_or_options.respond_to?(key)
          return unless context_or_options.respond_to?(:[])

          context_or_options[key] || context_or_options[key.to_s]
        end
      end

      module PricingResolver
        private

        def find_base_price
          existing_price = super
          dynamic_price = DynamicPrice.new(
            variant: context.variant,
            currency: context.currency,
            store: context.store
          ).resolve(fallback_price: existing_price)

          dynamic_price || existing_price
        end
      end

      module ProductCurrencyScope
        def with_currency(currency)
          explicit_prices = super
          store = Spree::Current.store || Spree::Store.default
          return explicit_prices unless DynamicPriceScope.available?(store, currency)

          source_product_ids = DynamicPriceScope.source_prices(store, currency).select("spree_variants.product_id")
          where(id: explicit_prices.select(:id)).or(where(id: source_product_ids)).distinct
        end
      end

      module VariantCurrencyScope
        def for_currency_and_available_price_amount(currency = nil)
          explicit_prices = super
          store = Spree::Current.store || Spree::Store.default
          return explicit_prices unless DynamicPriceScope.available?(store, currency)

          source_variant_ids = DynamicPriceScope.source_prices(store, currency).select("spree_variants.id")
          where(id: explicit_prices.select(:id)).or(where(id: source_variant_ids)).distinct
        end
      end

      module LineItemPricing
        def update_price
          return if order&.completed?

          context = Spree::Pricing::Context.from_order(variant, order, quantity: quantity)
          resolved_price = variant.price_for(context)
          return unless resolved_price&.amount.present?

          self.price = resolved_price.price_including_vat_for(tax_zone: tax_zone)
          self.price_list_id = resolved_price.price_list_id
          assign_attributes(Integrations.snapshot_attributes(resolved_price))
        end

        def recalculate_price
          return if order&.completed?

          context = Spree::Pricing::Context.from_order(variant, order, quantity: quantity)
          resolved_price = variant.price_for(context)
          return unless resolved_price&.amount.present?

          new_price = resolved_price.price_including_vat_for(tax_zone: tax_zone)
          return unless new_price.present?
          new_price_list_id = resolved_price.price_list_id
          snapshot = Integrations.snapshot_attributes(resolved_price)
          changed_snapshot = snapshot.any? { |attribute, value| public_send(attribute) != value }

          if new_price != price || new_price_list_id != price_list_id || changed_snapshot
            update_columns(snapshot.merge(price: new_price, price_list_id: new_price_list_id, updated_at: Time.current))
          end
        end

        def compare_at_amount
          if auto_currency_exchange_rate.present? && auto_currency_exchange_compare_at_amount.present?
            auto_currency_exchange_compare_at_amount * quantity
          else
            super
          end
        end

        private

        def update_price_from_modifier(currency, options)
          return if order&.completed?

          if currency
            resolved_price = variant.price_in(currency)
            return unless resolved_price&.amount.present?
          end

          super
          assign_attributes(Integrations.snapshot_attributes(resolved_price)) if resolved_price
        end
      end

      module OrderCurrencyPricing
        def update_line_item_price!(line_item)
          return if completed?

          context = Spree::Pricing::Context.from_order(line_item.variant, self, quantity: line_item.quantity)
          resolved_price = line_item.variant.price_for(context)

          if resolved_price&.amount
            line_item.update!(
              currency: currency,
              price: resolved_price.price_including_vat_for(tax_zone: line_item.tax_zone),
              price_list_id: resolved_price.price_list_id,
              **Integrations.snapshot_attributes(resolved_price)
            )
          else
            line_item.destroy
          end
        end
      end

      module DynamicPriceScope
        module_function

        def available?(store, currency)
          return false if store.blank? || currency.blank?
          return false unless Rate.table_exists?
          return false unless store_currency?(store, currency.to_s.upcase)

          base = store.default_currency.to_s.upcase
          target = currency.to_s.upcase
          target == base || Rate.exists?(store_id: store.id, base_currency: base, currency: target)
        end

        def source_prices(store, currency)
          base = store.default_currency.to_s.upcase
          target_rate = currency.to_s.upcase == base || Rate.exists?(store_id: store.id, base_currency: base, currency: currency.to_s.upcase)
          return Spree::Price.none unless target_rate

          store_base_prices = Spree::Price.base_prices.joins(variant: :product)
                                   .where(spree_products: { store_id: store.id })
                                   .where.not(amount: nil)
          store_base_prices = store_base_prices.where(min_quantity: 1) if quantity_breaks_supported?

          store_base_prices.where(currency: base).or(
            store_base_prices.where(
              "EXISTS (SELECT 1 FROM spree_auto_currency_exchange_rates source_rates " \
              "WHERE source_rates.store_id = ? AND source_rates.base_currency = ? " \
              "AND source_rates.currency = spree_prices.currency)",
              store.id,
              base
            )
          )
        end

        def store_currency?(store, currency)
          if store.respond_to?(:has_markets?) && store.has_markets?
            store.markets.where(currency: currency).exists?
          else
            store.supported_currencies_list.any? { |item| item.iso_code == currency }
          end
        end

        def quantity_breaks_supported?
          Spree::Price.column_names.include?("min_quantity")
        end
      end

      def self.install!
        Spree::Market.include(MarketCallbacks) unless Spree::Market < MarketCallbacks
        Spree::Store.include(StoreCallbacks) unless Spree::Store < StoreCallbacks
        Spree::Price.include(PriceSnapshotAttributes) unless Spree::Price < PriceSnapshotAttributes
        Spree::Variant.prepend(VariantPricing) unless Spree::Variant.ancestors.include?(VariantPricing)
        if defined?(Spree::Pricing::Resolver) && !Spree::Pricing::Resolver.ancestors.include?(PricingResolver)
          Spree::Pricing::Resolver.prepend(PricingResolver)
        end
        Spree::LineItem.prepend(LineItemPricing) unless Spree::LineItem.ancestors.include?(LineItemPricing)
        Spree::Order.prepend(OrderCurrencyPricing) unless Spree::Order.ancestors.include?(OrderCurrencyPricing)

        if Spree::Product.respond_to?(:with_currency) && !Spree::Product.singleton_class.ancestors.include?(ProductCurrencyScope)
          Spree::Product.singleton_class.prepend(ProductCurrencyScope)
        end
        if Spree::Variant.respond_to?(:for_currency_and_available_price_amount) &&
           !Spree::Variant.singleton_class.ancestors.include?(VariantCurrencyScope)
          Spree::Variant.singleton_class.prepend(VariantCurrencyScope)
        end
      end

      def self.snapshot_attributes(price)
        rate = price&.auto_currency_exchange_rate
        {
          auto_currency_exchange_rate: rate,
          auto_currency_exchange_source_currency: rate ? price.auto_currency_exchange_source_currency : nil,
          auto_currency_exchange_source_amount: rate ? price.auto_currency_exchange_source_amount : nil,
          auto_currency_exchange_compare_at_amount: rate ? price.compare_at_amount : nil
        }
      end
    end
  end
end
