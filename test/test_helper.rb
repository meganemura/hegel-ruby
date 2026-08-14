# frozen_string_literal: true

# Coverage is opt-in (`rake coverage` sets COVERAGE=1) rather than always-on,
# so that running a single test file directly still works: an always-on
# 100% minimum would fail any partial run. SimpleCov.start must run before
# `require "hegel"` below, or the files it loads escape measurement.
if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start do
    # Restricts the report to lib/ and forces every matching file onto it,
    # even one that no test ever loads (0% coverage, still a real gap under
    # the 100% bar). lib/tasks/libhegel.rake is listed explicitly: its logic
    # lives in lib/ and test/hegel/test_locate.rb loads it, but a bare
    # "lib/**/*.rb" glob does not match a .rake extension.
    cover "lib/**/*.rb", "lib/tasks/libhegel.rake"

    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hegel"

# Use a build already fetched by `rake libhegel:fetch`, if any (a no-op otherwise: ENV#[]= with nil deletes).
ENV["HEGEL_LIBHEGEL_PATH"] ||= Dir[File.expand_path("../tmp/libhegel/*/*.{dylib,so,dll}", __dir__)].max

require "minitest/autorun"
