# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"

module Hegel
  # Copies Hegel.test's keyword arguments onto a libhegel settings handle.
  # Most keywords follow one rule: nil means "leave libhegel's own default in
  # place", so a caller of Hegel.test who passes none of them gets exactly
  # the engine's untouched defaults (100 test cases, a random seed, no
  # derandomize, every phase, every health check). +database+ and
  # +database_key+ follow the table #apply_database documents instead, and
  # +report_multiple_failures+ has no nil case at all -- see #apply's own
  # comment for why.
  module Settings
    # Hegel.test's verbosity: values, mapped to hegel.h's hegel_verbosity_t.
    VERBOSITY_CODES = {
      quiet: LibHegel::HEGEL_VERBOSITY_QUIET,
      normal: LibHegel::HEGEL_VERBOSITY_NORMAL,
      verbose: LibHegel::HEGEL_VERBOSITY_VERBOSE,
      debug: LibHegel::HEGEL_VERBOSITY_DEBUG
    }.freeze

    # Hegel.test's phases: Symbols, mapped to hegel.h's hegel_phase_t. The
    # engine ORs these together itself when every phase is passed; this table
    # only needs one bit per Symbol.
    PHASE_CODES = {
      explicit: LibHegel::HEGEL_PHASE_EXPLICIT,
      reuse: LibHegel::HEGEL_PHASE_REUSE,
      generate: LibHegel::HEGEL_PHASE_GENERATE,
      target: LibHegel::HEGEL_PHASE_TARGET,
      shrink: LibHegel::HEGEL_PHASE_SHRINK
    }.freeze

    # Hegel.test's suppress_health_check: Symbols, mapped to hegel.h's
    # hegel_health_check_t.
    HEALTH_CHECK_CODES = {
      filter_too_much: LibHegel::HEGEL_HC_FILTER_TOO_MUCH,
      too_slow: LibHegel::HEGEL_HC_TOO_SLOW,
      test_cases_too_large: LibHegel::HEGEL_HC_TEST_CASES_TOO_LARGE,
      large_initial_test_case: LibHegel::HEGEL_HC_LARGE_INITIAL_TEST_CASE
    }.freeze

    module_function

    # Applies every one of Hegel.test's settings keywords to +settings+ via
    # +impl+. +test_cases+, +seed+, +derandomize+, +verbosity+, +phases+, and
    # +suppress_health_check+ all skip their setter when left nil.
    # +database+/+database_key+ follow #apply_database's own table, called
    # unconditionally since even the nil/nil case has a setter to call (see
    # its comment). +report_multiple_failures+ is called unconditionally too,
    # with no nil case: Hegel.test defaults it to false rather than leaving
    # it nil, so this method never sees nil for it -- see Hegel::Runner.run's
    # own comment for why that default departs from every other keyword's
    # nil-means-engine-default rule.
    def apply(impl, ctx, settings, test_cases:, seed:, derandomize:, verbosity:, database:, database_key:, phases:,
      suppress_health_check:, report_multiple_failures:)
      impl.settings_set_test_cases(ctx, settings, test_cases) unless test_cases.nil?
      impl.settings_set_seed(ctx, settings, seed, true) unless seed.nil?
      impl.settings_set_derandomize(ctx, settings, derandomize) unless derandomize.nil?
      apply_verbosity(impl, ctx, settings, verbosity) unless verbosity.nil?
      apply_database(impl, ctx, settings, database: database, database_key: database_key)
      apply_phases(impl, ctx, settings, phases) unless phases.nil?
      apply_suppress_health_check(impl, ctx, settings, suppress_health_check) unless suppress_health_check.nil?
      impl.settings_set_report_multiple_failures(ctx, settings, report_multiple_failures)
    end

    # Split from #apply so the VERBOSITY_CODES lookup (one of several
    # keywords that can fail) is not buried inside the top-level sequence.
    def apply_verbosity(impl, ctx, settings, verbosity)
      code = VERBOSITY_CODES.fetch(verbosity) do
        raise Hegel::Error,
          "hegel: unknown verbosity #{verbosity.inspect}; expected one of #{VERBOSITY_CODES.keys.inspect}"
      end
      impl.settings_set_verbosity(ctx, settings, code)
    end

    # docs/adr/0009-turn-the-example-database-on-with-a-key.md decides this
    # table and the reasons behind it; read it before changing this method.
    #
    #   database_key: | database: | does
    #   nil           | nil       | settings_set_database(ctx, s, "")
    #   nil           | String    | raises Hegel::Error
    #   String        | nil       | settings_set_database_key(ctx, s, key) only
    #   String        | String    | settings_set_database(ctx, s, database), then settings_set_database_key
    #
    # The nil/nil row calls settings_set_database("") explicitly rather than
    # leaving it uncalled, unlike every other nil-means-default keyword here:
    # the ADR measured that an unkeyed run writes nothing even with the
    # engine's own default path left in place, but that is behaviour this
    # project measured against one libhegel build, not a promise the header
    # makes, and the cost of relying on it being wrong is a directory
    # appearing in a caller's working copy that never asked for one.
    def apply_database(impl, ctx, settings, database:, database_key:)
      if database_key.nil?
        unless database.nil?
          raise Hegel::Error,
            "hegel: database: needs database_key: to scope what it stores and replays; " \
              "pass database_key: too, or drop database: and pass neither."
        end
        impl.settings_set_database(ctx, settings, "")
      else
        impl.settings_set_database(ctx, settings, database) unless database.nil?
        impl.settings_set_database_key(ctx, settings, database_key)
      end
    end

    # Split from #apply so the PHASE_CODES lookup and the OR-together step
    # are not buried inside the top-level sequence, the same reason
    # #apply_verbosity is split out. Raises Hegel::Error for a Symbol not in
    # PHASE_CODES, or for an empty Array: HEGEL_PHASE_* bits are additive
    # (each one turns a phase on), and mask 0 -- what an empty Array would
    # OR together to -- has not been measured against libhegel, unlike
    # dropping a single named phase (see the class-level phases: keyword
    # documentation this backs). Rejecting it here matches
    # #apply_verbosity's own precedent: refuse at the boundary with a
    # message naming the accepted values, rather than pass through a
    # combination nobody has watched the engine handle.
    def apply_phases(impl, ctx, settings, phases)
      mask = mask_for(phases, PHASE_CODES, "phases")
      impl.settings_set_phases(ctx, settings, mask)
    end

    # Split from #apply for the same reason #apply_phases is. Raises
    # Hegel::Error for a Symbol not in HEALTH_CHECK_CODES, or for an empty
    # Array, aligned with #apply_phases's own empty-Array rule so the two
    # keywords read the same way. The alignment is deliberate even though
    # the two are not symmetric: 0 here is the well-documented default (no
    # suppression), whereas nil already spells that meaning for this
    # keyword -- "no suppression" is nil, and an empty Array is rejected the
    # same way phases: [] is, rather than accepted as a second spelling of
    # nil.
    def apply_suppress_health_check(impl, ctx, settings, checks)
      mask = mask_for(checks, HEALTH_CHECK_CODES, "suppress_health_check")
      impl.settings_set_suppress_health_check(ctx, settings, mask)
    end

    # Shared by #apply_phases and #apply_suppress_health_check: looks up
    # every Symbol in +values+ against +codes+ and ORs the results together.
    # +keyword+ is the Hegel.test keyword being applied, named in both
    # raised messages so a caller who passes a bad Symbol to either one is
    # told which they got wrong -- the same reason #apply_verbosity's own
    # message says "verbosity". +codes+.keys appears there the same way
    # VERBOSITY_CODES.keys does in that method's.
    def mask_for(values, codes, keyword)
      if values.empty?
        raise Hegel::Error,
          "hegel: #{keyword} expects one or more of #{codes.keys.inspect}, got an empty Array"
      end

      values.reduce(0) do |mask, value|
        code = codes.fetch(value) do
          raise Hegel::Error, "hegel: unknown #{keyword} #{value.inspect}; expected one of #{codes.keys.inspect}"
        end
        mask | code
      end
    end
  end
end
