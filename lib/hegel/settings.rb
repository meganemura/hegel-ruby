# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"

module Hegel
  # Copies Hegel.test's keyword arguments onto a libhegel settings handle,
  # one hegel_settings_set_* call per non-nil keyword. nil is the single rule
  # for "leave libhegel's own default in place" across all four keywords, so
  # a caller of Hegel.test who passes none of them gets exactly the engine's
  # untouched defaults (100 test cases, a random seed, no derandomize).
  #
  # hegel_settings_set_database is not covered here: disabling the example
  # database is mandatory (see CLAUDE.md), not a keyword a caller chooses, so
  # Hegel::Runner calls it directly instead of routing it through this table.
  module Settings
    # Hegel.test's verbosity: values, mapped to hegel.h's hegel_verbosity_t.
    VERBOSITY_CODES = {
      quiet: LibHegel::HEGEL_VERBOSITY_QUIET,
      normal: LibHegel::HEGEL_VERBOSITY_NORMAL,
      verbose: LibHegel::HEGEL_VERBOSITY_VERBOSE,
      debug: LibHegel::HEGEL_VERBOSITY_DEBUG
    }.freeze

    module_function

    # Applies +test_cases+, +seed+, +derandomize+, and +verbosity+ to
    # +settings+ via +impl+, skipping any keyword left nil. Raises
    # Hegel::Error for a +verbosity+ Symbol not in VERBOSITY_CODES.
    def apply(impl, ctx, settings, test_cases:, seed:, derandomize:, verbosity:)
      impl.settings_set_test_cases(ctx, settings, test_cases) unless test_cases.nil?
      impl.settings_set_seed(ctx, settings, seed, true) unless seed.nil?
      impl.settings_set_derandomize(ctx, settings, derandomize) unless derandomize.nil?
      apply_verbosity(impl, ctx, settings, verbosity) unless verbosity.nil?
    end

    # Split from #apply so the VERBOSITY_CODES lookup (the one keyword that
    # can fail) is not buried inside the four-way sequence above.
    def apply_verbosity(impl, ctx, settings, verbosity)
      code = VERBOSITY_CODES.fetch(verbosity) do
        raise Hegel::Error,
          "hegel: unknown verbosity #{verbosity.inspect}; expected one of #{VERBOSITY_CODES.keys.inspect}"
      end
      impl.settings_set_verbosity(ctx, settings, code)
    end
  end
end
