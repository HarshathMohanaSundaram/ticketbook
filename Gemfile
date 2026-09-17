source "https://rubygems.org"

ruby "3.3.6"

gem "rails", "~> 7.2.0"
gem "pg", "~> 1.5"
gem "puma", ">= 6.0"

# Background jobs + cache store
gem "redis", ">= 5.0"
gem "sidekiq", "~> 7.3"
# Schedules the sweeper. The per-hold expiry job is precise; the sweeper only
# repairs the display if a scheduled job is ever lost, so it runs every 15 min.
gem "sidekiq-cron"
# connection_pool 3.0 changed TimedStack#pop's arity; Sidekiq 7.3 still calls the
# old signature and its scheduler thread dies at boot. Stay on the 2.x line.
gem "connection_pool", "~> 3.0"

# Domain
gem "aasm"          # seat lifecycle: available -> held -> booked
gem "pundit"        # authorization


# Front end (no Node: importmap + the Tailwind standalone binary)
# sprockets-rails is what `rails new` generates, and tailwindcss-rails hooks its
# build onto assets:precompile -- without it, every rails command fails to load.
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "view_component"
gem "pagy"

# json 3.x removed the quirks_mode keyword that ActiveSupport 7.2's JSON encoder
# still passes, which blows up on every session cookie write. Stay on 2.x until
# Rails is upgraded.
gem "json", "~> 2.9"

gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end

group :test do
  # Required: the concurrency spec runs real threads, so transactional
  # fixtures are off and cleanup has to be truncation.
  gem "database_cleaner-active_record"
  gem "shoulda-matchers"
end

group :development do
  # Sign-in mails are captured, not sent: read them at /letter_opener.
  # The non-web letter_opener would try to launch a browser inside the container.
  gem "letter_opener_web"
  gem "annotaterb"
  gem "bullet"
  gem "web-console"
end