# frozen_string_literal: true

require "hegel/lib_hegel"

module Hegel
  module LibHegel
    # A configurable stand-in for LibHegel::Real, so logic built on top of
    # this boundary is testable without opening the native engine. This
    # file lives under test/support/, and hegeltest.gemspec's file list
    # drops everything under test/, so it never ships in the gem.
    #
    # Every value an implementation hands back (the version string, the
    # context's last-error message, and the result code #version reports)
    # is a plain accessor here, so a test can set exactly the condition it
    # wants to exercise — most usefully, an error code that drives
    # LibHegel.check! down a path the real engine would rarely take.
    class Fake
      # The handle #run_result_failure hands back. Bundles the origin and
      # blob a test configured at that index via #failure_origins= /
      # #failure_blobs=, so #failure_origin / #failure_reproduction_blob
      # can read them straight off the handle, mirroring how the real
      # ABI's opaque failure handle already carries that state.
      Failure = Struct.new(:origin, :blob)

      # Writers only: #version is also the name of the instance method
      # below that mimics the real ABI call, so an attr_accessor's 0-arity
      # reader would collide with (and be overwritten by) that method
      # definition. Nothing here needs to read a value back once set.
      attr_writer :version, :version_code, :last_error

      # One result-code knob per primitive below that can fail, all
      # defaulting to HEGEL_OK (set in #initialize) so a test only sets
      # the one it wants to drive down a specific LibHegel.check!
      # translation path. Mirrors the per-primitive return-code fields on
      # hegel-java's FakeLibhegel.
      attr_writer :settings_new_code, :settings_set_test_cases_code, :settings_set_verbosity_code,
        :settings_set_seed_code, :settings_set_derandomize_code, :settings_set_database_code,
        :run_start_code, :next_test_case_code, :mark_complete_code,
        :generate_boolean_code, :generate_integer_code,
        :run_result_code, :run_result_status_code, :run_result_error_code,
        :run_result_failure_count_code, :run_result_failure_code,
        :failure_origin_code, :failure_reproduction_blob_code, :test_case_from_blob_code

      # Values #generate_boolean / #generate_integer hand back on success.
      attr_writer :generate_boolean_value, :generate_integer_value

      # Number of test cases #next_test_case yields before reporting the
      # run finished (an out-parameter of NULL, not an error).
      attr_writer :test_case_count

      # Value #run_result_status hands back on success (one of the
      # HEGEL_RUN_STATUS_* constants).
      attr_writer :run_result_status_value

      # Value #run_result_error hands back on success. nil (the default)
      # models a run that completed normally; a String models an errored
      # run's message.
      attr_writer :run_result_error_value

      # Number of failures #run_result_failure_count reports, and the
      # per-index origin / reproduction blob #run_result_failure's handle
      # carries. A blob of nil at a given index models libhegel producing
      # none for that failure.
      attr_writer :failure_count, :failure_origins, :failure_blobs

      # Whether #run_start's out-parameter comes back NULL despite a
      # HEGEL_OK result, distinct from an error via #run_start_code=.
      attr_writer :run_start_returns_nil

      attr_reader :freed_contexts, :marked_statuses, :marked_origins

      def initialize
        @version = Hegel::LIBHEGEL_VERSION
        @version_code = HEGEL_OK
        @last_error = "fake error"
        @freed_contexts = []

        @settings_new_code = HEGEL_OK
        @settings_set_test_cases_code = HEGEL_OK
        @settings_set_verbosity_code = HEGEL_OK
        @settings_set_seed_code = HEGEL_OK
        @settings_set_derandomize_code = HEGEL_OK
        @settings_set_database_code = HEGEL_OK

        @run_start_code = HEGEL_OK
        @run_start_returns_nil = false
        @next_test_case_code = HEGEL_OK
        @test_case_count = 0
        @cases_served = 0
        @mark_complete_code = HEGEL_OK
        @marked_statuses = []
        @marked_origins = []

        @generate_boolean_code = HEGEL_OK
        @generate_boolean_value = false
        @generate_integer_code = HEGEL_OK
        @generate_integer_value = 0

        @run_result_code = HEGEL_OK
        @run_result_status_code = HEGEL_OK
        @run_result_status_value = HEGEL_RUN_STATUS_PASSED
        @run_result_error_code = HEGEL_OK
        @run_result_error_value = nil
        @run_result_failure_count_code = HEGEL_OK
        @failure_count = 0
        @run_result_failure_code = HEGEL_OK
        @failure_origins = []
        @failure_blobs = []
        @failure_origin_code = HEGEL_OK
        @failure_reproduction_blob_code = HEGEL_OK
        @test_case_from_blob_code = HEGEL_OK
      end

      # A fresh, distinct handle per call; the only thing callers may do
      # with it is pass it back into another method on this instance.
      def context_new
        Object.new
      end

      # Records +ctx+ (including nil, matching libhegel's own no-op-on-NULL
      # contract) so a test can assert a context was released.
      def context_free(ctx)
        @freed_contexts << ctx
        nil
      end

      def context_last_error(_ctx)
        @last_error
      end

      # Returns #version, or raises the exception LibHegel.check!
      # translates #version_code to.
      def version(ctx)
        LibHegel.check!(self, ctx, @version_code)
        @version
      end

      def settings_new(ctx)
        LibHegel.check!(self, ctx, @settings_new_code)
        Object.new
      end

      def settings_free(_ctx, _s)
        nil
      end

      def settings_set_test_cases(ctx, _s, _n)
        LibHegel.check!(self, ctx, @settings_set_test_cases_code)
        nil
      end

      def settings_set_verbosity(ctx, _s, _v)
        LibHegel.check!(self, ctx, @settings_set_verbosity_code)
        nil
      end

      def settings_set_seed(ctx, _s, _seed, _has_seed)
        LibHegel.check!(self, ctx, @settings_set_seed_code)
        nil
      end

      def settings_set_derandomize(ctx, _s, _derandomize)
        LibHegel.check!(self, ctx, @settings_set_derandomize_code)
        nil
      end

      def settings_set_database(ctx, _s, _database)
        LibHegel.check!(self, ctx, @settings_set_database_code)
        nil
      end

      # Returns nil instead of a handle when @run_start_returns_nil is set,
      # a case distinct from @run_start_code driving an error: this models
      # a successful call whose out-parameter is still NULL.
      def run_start(ctx, _settings)
        LibHegel.check!(self, ctx, @run_start_code)
        @run_start_returns_nil ? nil : Object.new
      end

      # Yields @test_case_count distinct handles, then nil (the run
      # finished), matching hegel_next_test_case's documented NULL-on-
      # completion contract.
      def next_test_case(ctx, _run)
        LibHegel.check!(self, ctx, @next_test_case_code)
        return nil if @cases_served >= @test_case_count

        @cases_served += 1
        Object.new
      end

      def run_free(_ctx, _run)
        nil
      end

      def test_case_free(_ctx, _tc)
        nil
      end

      # Records +status+ and +origin+ (readable via #marked_statuses /
      # #marked_origins) before translating @mark_complete_code, so a test
      # can see what was passed even when driving an error path.
      def mark_complete(ctx, _tc, status, origin)
        @marked_statuses << status
        @marked_origins << origin
        LibHegel.check!(self, ctx, @mark_complete_code)
        nil
      end

      def generate_boolean(ctx, _tc, _p, _forced, _has_forced)
        LibHegel.check!(self, ctx, @generate_boolean_code)
        @generate_boolean_value
      end

      def generate_integer(ctx, _tc, _min_value, _max_value)
        LibHegel.check!(self, ctx, @generate_integer_code)
        @generate_integer_value
      end

      def run_result(ctx, _run)
        LibHegel.check!(self, ctx, @run_result_code)
        Object.new
      end

      def run_result_free(_ctx, _r)
        nil
      end

      def run_result_status(ctx, _r)
        LibHegel.check!(self, ctx, @run_result_status_code)
        @run_result_status_value
      end

      def run_result_error(ctx, _r)
        LibHegel.check!(self, ctx, @run_result_error_code)
        @run_result_error_value
      end

      def run_result_failure_count(ctx, _r)
        LibHegel.check!(self, ctx, @run_result_failure_count_code)
        @failure_count
      end

      # Returns a Failure bundling the origin / blob configured at +index+
      # via #failure_origins= / #failure_blobs=.
      def run_result_failure(ctx, _r, index)
        LibHegel.check!(self, ctx, @run_result_failure_code)
        Failure.new(@failure_origins[index], @failure_blobs[index])
      end

      def failure_free(_ctx, _f)
        nil
      end

      def failure_origin(ctx, f)
        LibHegel.check!(self, ctx, @failure_origin_code)
        f.origin
      end

      def failure_reproduction_blob(ctx, f)
        LibHegel.check!(self, ctx, @failure_reproduction_blob_code)
        f.blob
      end

      def test_case_from_blob(ctx, _settings, _blob)
        LibHegel.check!(self, ctx, @test_case_from_blob_code)
        Object.new
      end
    end
  end
end
