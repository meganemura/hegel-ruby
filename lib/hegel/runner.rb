# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"
require_relative "settings"
require_relative "test_case"

module Hegel
  # Drives one Hegel.test run: this is the Ruby side of the per-test-case
  # lifecycle hegel-rust's src/run_lifecycle.rs calls `drive`. Ruby owns the
  # loop; libhegel owns generation, shrinking, and (on failure) database
  # replay, so a user's test body never has to cross the FFI boundary itself.
  module Runner
    # Say the process is ending, not that a property failed. Catching one of
    # these as a counterexample would have the engine spend its shrink budget
    # minimising an interrupt instead of letting the process exit. Held as a
    # constant, not a literal `rescue Interrupt, SignalException, ...` list,
    # so #classify only names it once.
    FATAL_EXCEPTIONS = [Interrupt, SignalException, SystemExit, NoMemoryError].freeze

    # #origin_for's fallback when an exception's backtrace has no first
    # location to build a real origin from. Named the way hegel-rust names
    # its own equivalent constant, "Panic at <unknown>", for a panic with no
    # location.
    UNKNOWN_ORIGIN = "Raised at <unknown>"

    # hegel_run_result_error's fallback: the header documents a NULL message
    # as possible for an ERROR run, and Hegel::Error still needs *some*
    # message text in that case.
    UNKNOWN_RUN_ERROR_MESSAGE = "hegel: the run failed without an error message"

    module_function

    # Runs +block+ as a Hegel property against +impl+, applying +test_cases+,
    # +seed+, +derandomize+, and +verbosity+ (see Hegel::Settings) to a fresh
    # settings handle first. Returns nil on a passing run, re-raises the
    # exception the smallest failing case's body raised on a failing run, and
    # raises Hegel::Error for a run-level failure (ERROR status, or a replay
    # that could not reproduce the recorded failure).
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
    def run(impl:, test_cases: nil, seed: nil, derandomize: nil, verbosity: nil, &block)
      LibHegel.with_context(impl) do |ctx|
        settings = impl.settings_new(ctx)
        begin
          Settings.apply(impl, ctx, settings, test_cases: test_cases, seed: seed, derandomize: derandomize,
            verbosity: verbosity)
          # Mandatory, not a keyword: hegel_settings_new defaults to writing
          # ./.hegel/examples/ on use, and this library does not support the
          # database yet (see CLAUDE.md). An empty string disables it.
          impl.settings_set_database(ctx, settings, "")

          run = impl.run_start(ctx, settings)
          begin
            drive(impl, ctx, run, &block)

            result = impl.run_result(ctx, run)
            begin
              finish(impl, ctx, settings, result, &block)
            ensure
              impl.run_result_free(ctx, result)
            end
          ensure
            # hegel_run_free only marks an in-progress case complete; per the
            # header it does not free the test-case handle itself. That
            # handle is this loop's own to release, which #run_case already
            # does in its own `ensure` on every path, including a fatal
            # exception raised from inside #drive.
            impl.run_free(ctx, run)
          end
        ensure
          impl.settings_free(ctx, settings)
        end
      end
    end

    # Pulls test cases from +run+ until hegel_next_test_case reports none
    # left (a nil out-parameter, not an error). Never counts iterations:
    # test_cases bounds generation, not how many times shrinking calls the
    # body afterwards. Measured against libhegel 0.32.5, a run configured for
    # 20 test cases whose body always failed took 1003 iterations.
    def drive(impl, ctx, run, &block)
      loop do
        tc = impl.next_test_case(ctx, run)
        break if tc.nil?

        run_case(impl, ctx, tc, &block)
      end
    end

    # Runs +block+ against one test-case handle, classifies the outcome, and
    # reports it with hegel_mark_complete. A fatal exception (#classify
    # re-raises those before returning) skips mark_complete entirely and
    # still reaches the `ensure` below, so the handle is freed either way;
    # its owner is this loop, not hegel_run_free (see #run's comment above).
    def run_case(impl, ctx, tc, &block)
      status, origin = classify(impl, ctx, tc, &block)
      impl.mark_complete(ctx, tc, status, origin)
    ensure
      impl.test_case_free(ctx, tc)
    end

    # Reads the finished run's status and acts on it. PASSED returns nil,
    # ERROR raises Hegel::Error from hegel_run_result_error's message, and
    # FAILED hands off to #replay. Any other status would mean this binding
    # does not recognise a hegel_run_status_t value the loaded engine
    # returned, mirroring how LibHegel.check! names an unrecognised result
    # code instead of silently doing nothing with it.
    def finish(impl, ctx, settings, result, &block)
      status = impl.run_result_status(ctx, result)
      case status
      when LibHegel::HEGEL_RUN_STATUS_PASSED
        nil
      when LibHegel::HEGEL_RUN_STATUS_ERROR
        raise Hegel::Error, impl.run_result_error(ctx, result) || UNKNOWN_RUN_ERROR_MESSAGE
      when LibHegel::HEGEL_RUN_STATUS_FAILED
        replay(impl, ctx, settings, result, &block)
      else
        raise Hegel::Error, "hegel: run finished with an unrecognized status (#{status})"
      end
    end

    # Replays every recorded failure by running +block+ again against a test
    # case rebuilt from its reproduction blob, in the same way #run_case
    # classifies and completes a live one. Raises the last replay's kept
    # exception unconditionally, with no nil guard: #finish only reaches
    # here on a FAILED run, and a FAILED run this binding has actually seen
    # always carries at least one failure to iterate below, so a guard would
    # add a branch no test could reach without contriving a run this binding
    # has never observed.
    def replay(impl, ctx, settings, result, &block)
      kept_exception = nil
      impl.run_result_failure_count(ctx, result).times do |index|
        failure = impl.run_result_failure(ctx, result, index)
        begin
          kept_exception = replay_failure(impl, ctx, settings, failure, index, &block)
        ensure
          impl.failure_free(ctx, failure)
        end
      end
      raise kept_exception
    end

    # Rebuilds one failure's test case from its reproduction blob and runs
    # +block+ against it, through the same #classify used by the live loop.
    #
    # Flaky is "not INTERESTING", not "did not raise": #classify's other two
    # non-INTERESTING outcomes both matter here. A body that raises nothing
    # on replay is the textbook flaky case, but a stale blob replays into
    # Hegel::StopTest too (the header documents hegel_test_case_from_blob's
    # HEGEL_E_STOP_TEST for "a blob whose choices no longer match the
    # caller's generators"), and #classify already turns that into OVERRUN.
    # Re-raising either as its original class would leak a control exception
    # meant only for code driving a test case into the host test framework —
    # exactly what this classify-then-check step exists to prevent.
    def replay_failure(impl, ctx, settings, failure, index, &block)
      blob = impl.failure_reproduction_blob(ctx, failure)
      raise Hegel::Error, "hegel: failure #{index} has no reproduction blob" if blob.nil?

      tc = impl.test_case_from_blob(ctx, settings, blob)
      begin
        status, origin, exception = classify(impl, ctx, tc, &block)
        raise Hegel::Error, flaky_message unless status == LibHegel::HEGEL_STATUS_INTERESTING

        # The libhegel reference documents blob replay as ended by the
        # caller's own hegel_mark_complete. Skipping it might not crash
        # hegel_test_case_free, but not crashing is not the same as correct.
        impl.mark_complete(ctx, tc, status, origin)
        exception
      ensure
        impl.test_case_free(ctx, tc)
      end
    end

    # Runs +block+ against +tc+ and classifies the outcome into the
    # [hegel_status_t, origin, exception] #run_case and #replay_failure both
    # need. Order matters: a fatal exception must be re-raised before it
    # reaches the library's own control exceptions, which must themselves be
    # told apart from an ordinary exception before the catch-all below.
    #
    # standard:disable Lint/RescueException -- `rescue Exception` is
    # deliberate: Minitest::Assertion and RSpec's ExpectationNotMetError both
    # descend from Exception, not StandardError, so a narrower rescue would
    # let a failing assertion pass through this loop uncaught instead of
    # being reported as a Hegel failure.
    def classify(impl, ctx, tc, &block)
      block.call(TestCase.new(impl, ctx, tc))
      [LibHegel::HEGEL_STATUS_VALID, nil, nil]
    rescue *FATAL_EXCEPTIONS
      raise
    rescue Hegel::AssumeFailed
      [LibHegel::HEGEL_STATUS_INVALID, nil, nil]
    rescue Hegel::StopTest
      [LibHegel::HEGEL_STATUS_OVERRUN, nil, nil]
    rescue Exception => e
      [LibHegel::HEGEL_STATUS_INTERESTING, origin_for(e), e]
    end
    # standard:enable Lint/RescueException

    # Builds a stable origin string from where +exception+ was raised, the
    # same information hegel-rust's own "Panic at {location}" origin uses.
    # The exception's class is deliberately left out: two failures raised at
    # the same line are the same bug even if the raised class differs run to
    # run (e.g. a NoMethodError on one nil and a TypeError on another), and
    # hegel_mark_complete's header is explicit that origin is what groups
    # failures for shrinking.
    def origin_for(exception)
      location = exception.backtrace_locations&.first
      location ? "Raised at #{location.path}:#{location.lineno}" : UNKNOWN_ORIGIN
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
  end
end
