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
    # the 100% bar). The two .rake files are listed explicitly: their logic
    # lives in lib/ and test/hegel/test_locate.rb and test_platform_gems.rb
    # load them, but a bare "lib/**/*.rb" glob does not match a .rake
    # extension.
    cover "lib/**/*.rb", "lib/tasks/libhegel.rake", "lib/tasks/platform_gems.rake"

    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hegel"

# Use a build already fetched by `rake libhegel:fetch` (or `fetch_all`), if
# any. Globs this host's own asset name specifically, not every asset under
# tmp/libhegel/: `fetch_all` stages every published platform's asset in the
# same tmp/libhegel/<version>/ directory, and a bare wildcard's `.max` would
# then pick whichever platform's filename sorts last, not this host's own.
# A no-op on an unsupported host, or otherwise: ENV#[]= with nil deletes.
host_asset = begin
  Hegel::Locate.asset_name(host_cpu: RbConfig::CONFIG["host_cpu"], host_os: RbConfig::CONFIG["host_os"])
rescue Hegel::Error
  nil
end
ENV["HEGEL_LIBHEGEL_PATH"] ||= host_asset && Dir[File.expand_path("../tmp/libhegel/*/#{host_asset}", __dir__)].max

require "minitest/autorun"
