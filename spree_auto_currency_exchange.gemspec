# frozen_string_literal: true

require_relative "lib/spree/auto_currency_exchange/version"

Gem::Specification.new do |spec|
  spec.name = "spree_auto_currency_exchange"
  spec.version = Spree::AutoCurrencyExchange::VERSION
  spec.authors = ["Rexomi"]
  spec.email = []
  spec.summary = "Dynamic market currency pricing for Spree Commerce"
  spec.description = "Converts Spree variant prices at runtime using centrally refreshed exchange rates."
  spec.homepage = "https://github.com/Rexomi/spree-auto-currency-exchange"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/Rexomi/spree-auto-currency-exchange/issues",
    "changelog_uri" => "https://github.com/Rexomi/spree-auto-currency-exchange/releases",
    "documentation_uri" => "https://github.com/Rexomi/spree-auto-currency-exchange#readme",
    "source_code_uri" => "https://github.com/Rexomi/spree-auto-currency-exchange"
  }

  spec.files = Dir["{app,config,db,lib,spec}/**/*", "README.md", "LICENSE", "Rakefile", ".env.example"]
  spec.require_paths = ["lib"]

  if ENV["RAILS_VERSION"]
    spec.add_dependency "rails", ENV["RAILS_VERSION"]
  else
    spec.add_dependency "rails", ">= 7.2", "< 8.2"
  end

  if ENV["SPREE_CORE_VERSION"]
    spec.add_dependency "spree_core", ENV["SPREE_CORE_VERSION"]
  else
    spec.add_dependency "spree_core", ">= 5.6", "< 6.1"
  end
  # Rails relies on the host's zoneinfo database on Unix. This data gem makes
  # IANA store timezones available on platforms such as Windows as well.
  spec.add_dependency "tzinfo-data", "~> 1.2020"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "sqlite3", ">= 1.6", "< 3"
end
