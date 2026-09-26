# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in hegeltest.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "standard", "~> 1.3"

# Coverage measurement only; `COVERAGE=1 rake coverage` turns it on so a
# plain `rake test` run stays fast and works on a single file.
gem "simplecov", "1.0.3"

# Mutation testing only; `bundle exec mutineer run` reads it. Pinned exact,
# and never required at load time, so the library and its tests do not see it.
gem "mutineer", "1.0.2", require: false
