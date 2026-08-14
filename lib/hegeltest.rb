# frozen_string_literal: true

# Bundler derives its automatic require from the gem name, so a gem published
# as `hegeltest` must answer to `require "hegeltest"`. The library itself lives
# in `hegel.rb` and the documented form is `require "hegel"`; this file exists
# so that `gem "hegeltest"` works without a `require:` option.
require_relative "hegel"
