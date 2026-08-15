# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"
require_relative "report"
require_relative "settings"
require_relative "test_case"

module Hegel
  # Drives one Hegel.test run: this is the Ruby side of the per-test-case
  # lifecycle hegel-rust's src/run_lifecycle.rs calls `drive`. Ruby owns the
  # loop; libhegel owns generation, shrinking, and (on failure) database
  # replay, so a user's test body never has to cross the FFI boundary itself.
  module Runner
    # #origin_for's fallback when an exception's backtrace has no first
    # location to build a real origin from. Named the way hegel-rust names
    # its own equivalent constant, "Panic at <unknown>", for a panic with no
    # location.
    UNKNOWN_ORIGIN = "Raised at <unknown>"

    # #infrastructure? treats a backtrace path as this library's own when it
    # falls under this directory. It is lib/, one above runner.rb's own
    # __dir__, so that hegel.rb and hegeltest.rb count too: Hegel.test lives
    # in hegel.rb, and its frame sits below every frame a property body
    # raises through. A property defined inside some other gem — a shared
    # test-helper gem calling Hegel.test on its caller's behalf — would
    # otherwise leave hegel.rb as the first frame belonging to nobody, and
    # name this library as the origin of the caller's own bug.
    #
    # A trailing separator makes the prefix match a directory boundary
    # rather than a string prefix, so a sibling directory that merely
    # starts with the same characters (lib/hegelx/) cannot match.
    LIBRARY_DIR = File.expand_path("..", __dir__) + File::SEPARATOR

    # Every directory an installed gem's own files live under. Gem.path lists
    # each root RubyGems searches (the default gem home plus $GEM_PATH), and
    # each root keeps installed gems under a "gems/" subdirectory -- the
    # structure a test framework such as minitest or rspec-expectations is
    # installed into. A caller's own code loaded via a Gemfile `path:` or
    # `git:` entry lives in the working copy instead, so this rule cannot
    # mistake it for a framework's own frame (see docs/adr/0012). Read once,
    # when this file is first required: under Bundler, that require happens
    # after Bundler has already set the gem paths this process uses, so the
    # list this constant freezes is the one every later frame is checked
    # against.
    INSTALLED_GEM_DIRS = Gem.path.map { |path| File.join(path, "gems") + File::SEPARATOR }.freeze

    # Ruby's own standard library, e.g. the minitest release Ruby itself
    # bundles rather than one RubyGems installed -- a second way a test
    # framework's own frame can appear that INSTALLED_GEM_DIRS alone would
    # not catch.
    STDLIB_DIR = RbConfig::CONFIG["rubylibdir"] + File::SEPARATOR

    # hegel_run_result_error's fallback: the header documents a NULL message
    # as possible for an ERROR run, and Hegel::Error still needs *some*
    # message text in that case.
    UNKNOWN_RUN_ERROR_MESSAGE = "hegel: the run failed without an error message"

    # Counts test cases as #drive receives them from the live run loop, and
    # snapshots, per distinct origin, how many had been returned (and how
    # many of those were discarded) the first time that origin's exception
    # was classified INTERESTING. That snapshot is the failure report's own
    # "Falsified after N test cases (M discarded)" line: the generation
    # phase's counts, not the shrink phase's -- #drive's own comment
    # measured the shrink phase at roughly 50x more iterations for a
    # similarly sized run, and counting those into N would answer a
    # different question than the report claims to.
    class GenerationStats
      def initialize
        @test_cases = 0
        @discarded = 0
        @snapshots = {}
      end

      # Called once per case #drive receives (or, from #reproduce, exactly
      # once for its own single case).
      def record(status, origin)
        @test_cases += 1
        @discarded += 1 if status == LibHegel::HEGEL_STATUS_INVALID
        @snapshots[origin] ||= [@test_cases, @discarded] if status == LibHegel::HEGEL_STATUS_INTERESTING
      end

      # [test_cases, discarded] as of +origin+'s first INTERESTING
      # appearance. No fallback: every origin #replay_failure asks for here
      # came from a failure hegel_run_result reported, and that failure
      # exists only because this same #record already saw it live.
      def for(origin)
        @snapshots.fetch(origin)
      end
    end

    module_function

    # Runs +block+ as a Hegel property against +impl+, applying +test_cases+,
    # +seed+, +derandomize+, +verbosity+, +database+, +database_key+,
    # +phases+, +suppress_health_check+, +report_multiple_failures+, and
    # +stateful_step_count+ (see Hegel::Settings) to a fresh settings handle
    # first. Returns nil on a passing run, re-raises the exception the
    # smallest failing case's body raised on a failing run, and raises
    # Hegel::Error for a run-level failure (ERROR status, a replay that
    # could not reproduce the recorded failure, or more than one distinct
    # failure -- see #replay).
    #
    # +database+ and +database_key+ follow the table
    # Hegel::Settings.apply_database documents; docs/adr/0009 has the
    # decision and the measurements behind it.
    #
    # +report_multiple_failures+ defaults to false, not nil: hegel-c/src/
    # settings.rs itself defaults to true, but hegel-rust's own Rust API
    # (src/runner.rs) and hegel-java both default to false, and hegel-java
    # states the reason -- re-raising one failure's own exception, unaltered,
    # is far kinder to a debugger and a stack trace than a summary would be.
    # That is this library's own central promise (#classify re-raises a
    # body's exception with its class and backtrace intact), so the same
    # reason applies here, and choosing to depart from the engine's own
    # default is itself a decision worth stating explicitly with `false`
    # rather than leaving it to a nil a reader could mistake for "no
    # opinion".
    #
    # +reproduce_failure+, when given, wins over everything above except
    # +verbosity+: it skips the run loop entirely and replays a single case
    # built from that blob (see #reproduce). +test_cases+ has no run to
    # bound in that case.
    #
    # +output+ (default $stderr) is where a failure report is written,
    # unless +verbosity+ is :quiet, in which case none is written at all.
    #
    # Handles nest context > settings > run > result, each freed in an
    # `ensure` by the code that opened it, innermost first: hegel_context_free
    # requires every other handle taken from the context to be freed first,
    # and Ruby's GC gives finalizers no ordering guarantee to rely on instead.
    #
    # +settings+ stays open through the whole run, not just through
    # hegel_run_start. The header says a caller may free settings as soon as
    # hegel_run_start returns, but that is only true for driving the loop: a
    # failing run's replay calls hegel_test_case_from_blob against this same
    # settings handle, so it must outlive the FAILED-status replay below, not
    # just the loop above it.
    def run(impl:, test_cases: nil, seed: nil, derandomize: nil, verbosity: nil, database: nil, database_key: nil,
      phases: nil, suppress_health_check: nil, report_multiple_failures: false, stateful_step_count: nil,
      output: $stderr, reproduce_failure: nil, &block)
      quiet = verbosity == :quiet
      LibHegel.with_context(impl) do |ctx|
        settings = impl.settings_new(ctx)
        begin
          Settings.apply(impl, ctx, settings, test_cases: test_cases, seed: seed, derandomize: derandomize,
            verbosity: verbosity, database: database, database_key: database_key, phases: phases,
            suppress_health_check: suppress_health_check, report_multiple_failures: report_multiple_failures,
            stateful_step_count: stateful_step_count)

          if reproduce_failure
            reproduce(impl, ctx, settings, reproduce_failure, quiet: quiet, output: output, &block)
          else
            run_and_finish(impl, ctx, settings, quiet: quiet, output: output, &block)
          end
        ensure
          impl.settings_free(ctx, settings)
        end
      end
    end

    # The ordinary (non-reproduce_failure) path: starts a run, drives it,
    # and hands its result to #finish. Split out of #run so that path and
    # #reproduce's are two plain branches there, not one method doing both.
    def run_and_finish(impl, ctx, settings, quiet:, output:, &block)
      run = impl.run_start(ctx, settings)
      begin
        stats = GenerationStats.new
        drive(impl, ctx, run, stats, &block)

        result = impl.run_result(ctx, run)
        begin
          finish(impl, ctx, settings, result, stats, quiet: quiet, output: output, &block)
        ensure
          impl.run_result_free(ctx, result)
        end
      ensure
        # hegel_run_free only marks an in-progress case complete; per the
        # header it does not free the test-case handle itself. That
        # handle is this loop's own to release, which #run_case does via
        # #with_test_case's own `ensure` on every path, including a fatal
        # exception raised from inside #drive.
        impl.run_free(ctx, run)
      end
    end

    # Pulls test cases from +run+ until hegel_next_test_case reports none
    # left (a nil out-parameter, not an error). Never counts iterations
    # itself: test_cases bounds generation, not how many times shrinking
    # calls the body afterwards. Measured against libhegel 0.32.5, a run
    # configured for 20 test cases whose body always failed took 1003
    # iterations. +stats+ does its own, different counting -- see
    # GenerationStats above.
    def drive(impl, ctx, run, stats, &block)
      loop do
        tc = impl.next_test_case(ctx, run)
        break if tc.nil?

        run_case(impl, ctx, tc, stats, &block)
      end
    end

    # Builds a Hegel::TestCase for +tc+ and yields it, then frees what it
    # opened: every pool it recorded (Hegel::TestCase#free_pools), then the
    # test-case handle itself, in that order, whether the block returns or
    # raises. #run_case, #replay_failure, and #reproduce each need exactly
    # this shape around their own call to #classify -- docs/adr/0011 decides
    # a test case owns every pool built from it, and that pools free before
    # the handle that owns them goes.
    #
    # The nested `ensure` is what keeps those two releases independent. A
    # raise out of #free_pools would otherwise carry past the handle's own
    # release, and hegel_context_free requires every handle taken from the
    # context to be freed first, so one skipped release does not stop at one
    # leak -- it fails the context's release too, at the end of a run that
    # had already gone wrong enough to raise in here.
    def with_test_case(impl, ctx, tc, record: false)
      test_case = TestCase.new(impl, ctx, tc, record: record)
      yield test_case
    ensure
      begin
        test_case.free_pools
      ensure
        impl.test_case_free(ctx, tc)
      end
    end

    # Runs +block+ against one test-case handle, classifies the outcome,
    # counts it into +stats+, and reports it with hegel_mark_complete. A
    # fatal exception (#classify re-raises those before returning) skips
    # both entirely and still reaches #with_test_case's own `ensure`, so the
    # handle is freed either way; its owner is this loop, not hegel_run_free
    # (see #run_and_finish's comment above).
    def run_case(impl, ctx, tc, stats, &block)
      with_test_case(impl, ctx, tc) do |test_case|
        status, origin = classify(test_case, &block)
        stats.record(status, origin)
        impl.mark_complete(ctx, tc, status, origin)
      end
    end

    # Reads the finished run's status and acts on it. PASSED returns nil,
    # ERROR raises Hegel::Error from hegel_run_result_error's message, and
    # FAILED hands off to #replay. Any other status would mean this binding
    # does not recognise a hegel_run_status_t value the loaded engine
    # returned, mirroring how LibHegel.check! names an unrecognised result
    # code instead of silently doing nothing with it.
    def finish(impl, ctx, settings, result, stats, quiet:, output:, &block)
      status = impl.run_result_status(ctx, result)
      case status
      when LibHegel::HEGEL_RUN_STATUS_PASSED
        nil
      when LibHegel::HEGEL_RUN_STATUS_ERROR
        raise Hegel::Error, impl.run_result_error(ctx, result) || UNKNOWN_RUN_ERROR_MESSAGE
      when LibHegel::HEGEL_RUN_STATUS_FAILED
        replay(impl, ctx, settings, result, stats, quiet: quiet, output: output, &block)
      else
        raise Hegel::Error, "hegel: run finished with an unrecognized status (#{status})"
      end
    end

    # Replays every recorded failure by running +block+ again against a test
    # case rebuilt from its reproduction blob, in the same way #run_case
    # classifies and completes a live one. Writes the report for every
    # failure it collected to +output+ (unless +quiet+), then raises: one
    # failure re-raises its own kept exception, unaltered; two or more raise
    # Hegel::Error with #multiple_failures_message instead, since no single
    # one of several kept exceptions is more the run's own verdict than
    # another. hegel-rust's own src/run_lifecycle.rs (the
    # HEGEL_RUN_STATUS_FAILED branch) makes the same choice: one panic
    # re-raised as itself, several replaced by one panic carrying just the
    # count.
    #
    # #finish only reaches here on a FAILED run, and a FAILED run this
    # binding has actually seen always carries at least one failure to
    # iterate below, so neither raise needs a zero-failures guard: that
    # branch would need a run this binding has never observed to reach it.
    # The report is written before either raise, not after: a host
    # framework that catches the re-raised exception would otherwise read
    # its own output before this one, out of order.
    def replay(impl, ctx, settings, result, stats, quiet:, output:, &block)
      kept_exception = nil
      failures = []
      impl.run_result_failure_count(ctx, result).times do |index|
        failure = impl.run_result_failure(ctx, result, index)
        begin
          kept_exception, report = replay_failure(impl, ctx, settings, failure, index, stats, &block)
          failures << report
        ensure
          impl.failure_free(ctx, failure)
        end
      end
      output.puts(Report.render(failures)) unless quiet
      raise Hegel::Error, multiple_failures_message(failures.size) if failures.size > 1

      raise kept_exception
    end

    # Rebuilds one failure's test case from its reproduction blob and runs
    # +block+ against it, through the same #classify used by the live loop,
    # recording its entries for the report (see Hegel::TestCase). Returns
    # [exception, Hegel::Report::Failure] on success.
    #
    # Flaky is "not INTERESTING", not "did not raise": #classify's other two
    # non-INTERESTING outcomes both matter here. A body that raises nothing
    # on replay is the textbook flaky case. A blob whose choices no longer
    # match the caller's generators is the other one: the header puts that
    # at "the draw that overruns", so the body raises Hegel::StopTest and
    # #classify turns it into OVERRUN. Re-raising either as its original
    # class would leak a control exception meant only for code driving a
    # test case into the host test framework — exactly what this
    # classify-then-check step exists to prevent.
    def replay_failure(impl, ctx, settings, failure, index, stats, &block)
      blob = impl.failure_reproduction_blob(ctx, failure)
      raise Hegel::Error, "hegel: failure #{index} has no reproduction blob" if blob.nil?

      tc = build_replay_case(impl, ctx, settings, blob)
      with_test_case(impl, ctx, tc, record: true) do |test_case|
        status, origin, exception, entries = classify(test_case, &block)
        raise Hegel::Error, flaky_message unless status == LibHegel::HEGEL_STATUS_INTERESTING

        # The libhegel reference documents blob replay as ended by the
        # caller's own hegel_mark_complete. Skipping it might not crash
        # hegel_test_case_free, but not crashing is not the same as correct.
        impl.mark_complete(ctx, tc, status, origin)
        test_cases, discarded = stats.for(origin)
        [exception, Report::Failure.new(test_cases: test_cases, discarded: discarded, entries: entries, blob: blob)]
      end
    end

    # Hegel.test(reproduce_failure:)'s own path: starts no run loop, and
    # replays exactly one case built from +blob+, through the same
    # classify-then-check contract #replay_failure uses. That case is
    # already the "final" replay a report needs, so recording is on for it
    # -- unconditionally 1 test case, 0 discarded, since a body that raised
    # Hegel::AssumeFailed here would already have failed the status check
    # below before either count could matter.
    #
    # Builds the replay's test case, converting a control exception raised
    # while building it into an ordinary error.
    #
    # The header attributes HEGEL_E_STOP_TEST to "the draw that overruns"
    # rather than to this call, and replaying a two-draw blob against a
    # five-draw body does build a case and then overrun at a draw, measured
    # against 0.32.5. This guard is therefore defence rather than a
    # documented path: a control exception escaping into the caller's test
    # is the one outcome this whole design exists to prevent, and both
    # replay paths go through here so neither can grow the hole
    # independently.
    def build_replay_case(impl, ctx, settings, blob)
      impl.test_case_from_blob(ctx, settings, blob)
    rescue Hegel::StopTest
      raise Hegel::Error, flaky_message
    end

    def reproduce(impl, ctx, settings, blob, quiet:, output:, &block)
      tc = build_replay_case(impl, ctx, settings, blob)
      with_test_case(impl, ctx, tc, record: true) do |test_case|
        status, origin, exception, entries = classify(test_case, &block)
        raise Hegel::Error, flaky_message unless status == LibHegel::HEGEL_STATUS_INTERESTING

        impl.mark_complete(ctx, tc, status, origin)
        report = Report::Failure.new(test_cases: 1, discarded: 0, entries: entries, blob: blob)
        output.puts(Report.render([report])) unless quiet
        raise exception
      end
    end

    # Runs +block+ against +test_case+ (a Hegel::TestCase #with_test_case
    # already built, at whatever +record:+ it was given) and classifies the
    # outcome into the [hegel_status_t, origin, exception, entries]
    # #run_case, #replay_failure, and #reproduce all need. +entries+ is only
    # ever non-nil when +test_case+ was built to record and the outcome was
    # INTERESTING, since that is the only combination any caller here reads
    # it for. Order matters: a fatal exception must be re-raised before it
    # reaches the library's own control exceptions, which must themselves be
    # told apart from an ordinary exception before the catch-all below.
    #
    # standard:disable Lint/RescueException -- `rescue Exception` is
    # deliberate: Minitest::Assertion and RSpec's ExpectationNotMetError both
    # descend from Exception, not StandardError, so a narrower rescue would
    # let a failing assertion pass through this loop uncaught instead of
    # being reported as a Hegel failure.
    def classify(test_case, &block)
      block.call(test_case)
      [LibHegel::HEGEL_STATUS_VALID, nil, nil, nil]
    rescue *Hegel::FATAL_EXCEPTIONS
      raise
    rescue Hegel::AssumeFailed
      [LibHegel::HEGEL_STATUS_INVALID, nil, nil, nil]
    rescue Hegel::StopTest
      [LibHegel::HEGEL_STATUS_OVERRUN, nil, nil, nil]
    rescue Exception => e
      [LibHegel::HEGEL_STATUS_INTERESTING, origin_for(e), e, test_case.entries]
    end
    # standard:enable Lint/RescueException

    # Builds a stable origin string from where +exception+ was raised, the
    # same information hegel-rust's own "Panic at {location}" origin uses.
    # The exception's class is deliberately left out: two failures raised at
    # the same line are the same bug even if the raised class differs run to
    # run (e.g. a NoMethodError on one nil and a TypeError on another), and
    # hegel_mark_complete's header is explicit that origin is what groups
    # failures for shrinking.
    #
    # The first frame is not always the right one: an assertion library
    # raises from inside itself, so exception.backtrace_locations.first is a
    # line in minitest or rspec-support, identical for every failing
    # assertion in a suite regardless of which line the caller wrote (see
    # docs/adr/0012). #infrastructure? skips such frames in favor of the
    # first one that belongs to the caller's own code. When every frame is
    # infrastructure, the first frame is used after all: a coarse origin
    # still groups failures consistently, where no origin at all would lose
    # the failure's identity entirely.
    def origin_for(exception)
      locations = exception.backtrace_locations
      location = locations&.find { |candidate| !infrastructure?(candidate.path) } || locations&.first
      location ? "Raised at #{location.path}:#{location.lineno}" : UNKNOWN_ORIGIN
    end

    # True when +path+ belongs to this library, an installed gem, or Ruby's
    # own standard library, rather than to the caller whose test #origin_for
    # is trying to identify. Location, not framework name, is what this
    # checks: a list of framework names would need an entry per framework and
    # would be silently wrong the day someone uses one nobody added, the same
    # way the bug docs/adr/0012 fixes was silently wrong before it.
    def infrastructure?(path)
      path.start_with?(LIBRARY_DIR) ||
        INSTALLED_GEM_DIRS.any? { |dir| path.start_with?(dir) } ||
        path.start_with?(STDLIB_DIR)
    end

    # Mirrors the intent of hegel-rust's FLAKY_DIAGNOSTIC in English, not its
    # exact wording: the same generated data produced a different outcome on
    # replay, which usually means the body depends on something outside
    # libhegel's control.
    def flaky_message
      "hegel: this failure did not reproduce against the same generated data. " \
        "The test body likely depends on state outside libhegel's control, " \
        "such as a global variable, wall-clock time, or an external source of randomness."
    end

    # #replay's own multi-failure raise, and Report.render's multi-failure
    # heading, must stay the same sentence: a caller who greps the printed
    # report for this text should find the same string in the exception it
    # catches. Report.render builds that heading itself rather than calling
    # this method, since Hegel::Report only ever formats data handed to it
    # and does not know how a run ended (see its own class comment); the
    # sentence is duplicated here as the coupling between the two, not
    # factored into a shared helper neither module already depends on.
    # Deliberately carries no "hegel: " prefix, unlike #flaky_message and
    # the other messages this module composes itself (UNKNOWN_RUN_ERROR_
    # MESSAGE, the unrecognized-status message, the no-reproduction-blob
    # message), to stay that same sentence.
    def multiple_failures_message(count)
      "Property-based test failed with #{count} distinct failures."
    end
  end
end
