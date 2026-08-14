# frozen_string_literal: true

require "fiddle"
require_relative "../lib_hegel"

module Hegel
  module LibHegel
    # Drives libhegel's C ABI over Fiddle. Every other file works against
    # the plain Ruby values and method calls this class exposes, so a
    # future change to how the native call happens has exactly one file to
    # change.
    #
    # Opens the library and binds every function once, in #initialize, and
    # holds them for the instance's lifetime; each call below reuses the
    # already-bound function rather than re-resolving the symbol.
    class Real
      # Opens +path+ (default: Hegel::Locate.resolve) and binds the
      # functions this boundary calls. Immediately after, opens a context
      # of its own to compare the loaded engine's version against
      # Hegel::LIBHEGEL_VERSION, warning on +io+ (default $stderr) on a
      # mismatch; see LibHegel.warn_on_version_mismatch. +io+ exists so a
      # test can capture the warning instead of writing to the real stderr.
      def initialize(path = Hegel::Locate.resolve, io: $stderr)
        @handle = Fiddle.dlopen(path)

        @context_new_fn = bind("hegel_context_new", [], Fiddle::TYPE_VOIDP)
        @context_free_fn = bind("hegel_context_free", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @context_last_error_fn = bind("hegel_context_last_error", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
        @version_fn = bind("hegel_version", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

        @settings_new_fn = bind("hegel_settings_new", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @settings_free_fn = bind("hegel_settings_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @settings_set_test_cases_fn = bind(
          "hegel_settings_set_test_cases",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T],
          Fiddle::TYPE_INT
        )
        @settings_set_verbosity_fn = bind(
          "hegel_settings_set_verbosity",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
          Fiddle::TYPE_INT
        )
        @settings_set_seed_fn = bind(
          "hegel_settings_set_seed",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_BOOL],
          Fiddle::TYPE_INT
        )
        @settings_set_derandomize_fn = bind(
          "hegel_settings_set_derandomize",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_BOOL],
          Fiddle::TYPE_INT
        )
        @settings_set_database_fn = bind(
          "hegel_settings_set_database",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @run_start_fn = bind(
          "hegel_run_start",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @next_test_case_fn = bind(
          "hegel_next_test_case",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @run_free_fn = bind("hegel_run_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @test_case_free_fn = bind("hegel_test_case_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @mark_complete_fn = bind(
          "hegel_mark_complete",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @run_result_fn = bind(
          "hegel_run_result",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @run_result_free_fn = bind("hegel_run_result_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @run_result_status_fn = bind(
          "hegel_run_result_status",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @run_result_error_fn = bind(
          "hegel_run_result_error",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @run_result_failure_count_fn = bind(
          "hegel_run_result_failure_count",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @run_result_failure_fn = bind(
          "hegel_run_result_failure",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @failure_free_fn = bind("hegel_failure_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @failure_origin_fn = bind(
          "hegel_failure_origin",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @failure_reproduction_blob_fn = bind(
          "hegel_failure_reproduction_blob",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @test_case_from_blob_fn = bind(
          "hegel_test_case_from_blob",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
            Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @generate_boolean_fn = bind(
          "hegel_generate_boolean",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_BOOL, Fiddle::TYPE_BOOL,
            Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @generate_integer_fn = bind(
          "hegel_generate_integer",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT64_T, Fiddle::TYPE_INT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        LibHegel.with_context(self) { |ctx| LibHegel.warn_on_version_mismatch(self, ctx, io: io) }
      end

      # hegel_context_new never returns NULL (guaranteed by the header), so
      # the handle returned here is always live.
      def context_new
        @context_new_fn.call
      end

      # No-op when +ctx+ is nil: libhegel documents hegel_context_free as a
      # no-op on NULL, and a Ruby nil marshals to a NULL pointer for a
      # void* argument here, so no separate nil check is needed on this
      # side. The result code is not translated: the header documents this
      # call as always returning HEGEL_OK, so there is nothing to raise.
      def context_free(ctx)
        @context_free_fn.call(ctx)
        nil
      end

      # Copies the message out of libhegel's own buffer into a Ruby String
      # before returning, since the header documents that buffer as
      # borrowed and invalidated by the next call taking the same context.
      def context_last_error(ctx)
        @context_last_error_fn.call(ctx).to_s
      end

      # Returns the loaded engine's version string, or raises the
      # exception LibHegel.check! translates this call's result code to.
      def version(ctx)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @version_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.ptr.to_s
      end

      # Returns a settings handle initialized with libhegel's defaults, or
      # raises the exception LibHegel.check! translates this call's result
      # code to.
      def settings_new(ctx)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @settings_new_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # No-op when +s+ is nil, matching hegel_settings_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free: the header documents this call as always returning
      # HEGEL_OK.
      def settings_free(ctx, s)
        @settings_free_fn.call(ctx, s)
        nil
      end

      def settings_set_test_cases(ctx, s, n)
        code = @settings_set_test_cases_fn.call(ctx, s, n)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_verbosity(ctx, s, v)
        code = @settings_set_verbosity_fn.call(ctx, s, v)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_seed(ctx, s, seed, has_seed)
        code = @settings_set_seed_fn.call(ctx, s, seed, has_seed)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_derandomize(ctx, s, derandomize)
        code = @settings_set_derandomize_fn.call(ctx, s, derandomize)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +database+ may be nil (libhegel's own default path) or a String,
      # including "" to disable the database. A Ruby String passed for a
      # TYPE_VOIDP argument is marshalled as a pointer to its bytes by
      # Fiddle, which is what a const char* parameter needs here.
      def settings_set_database(ctx, s, database)
        code = @settings_set_database_fn.call(ctx, s, database)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +settings+ can be freed by the caller as soon as this call returns:
      # the header documents that hegel_run_start copies the settings it is
      # given rather than borrowing them. callback and user_data are always
      # NULL here, which the header documents as leaving libhegel's output
      # on stderr; wiring a Ruby-backed callback through Fiddle::Closure is
      # left to a later task.
      def run_start(ctx, settings)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @run_start_fn.call(ctx, settings, nil, nil, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns the next test case, or nil once the run has finished (the
      # header documents *out_test_case as NULL at that point, with a
      # HEGEL_OK result rather than an error).
      def next_test_case(ctx, run)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @next_test_case_fn.call(ctx, run, out)
        LibHegel.check!(self, ctx, code)
        out.ptr.null? ? nil : out.ptr
      end

      # No-op when +run+ is nil, matching hegel_run_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def run_free(ctx, run)
        @run_free_fn.call(ctx, run)
        nil
      end

      # No-op when +tc+ is nil, matching hegel_test_case_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def test_case_free(ctx, tc)
        @test_case_free_fn.call(ctx, tc)
        nil
      end

      # +origin+ must be non-nil only when +status+ is
      # HEGEL_STATUS_INTERESTING, per the header; this layer neither builds
      # nor validates that string, only passes through what the caller
      # supplies. A Ruby nil marshals to NULL for the TYPE_VOIDP argument.
      def mark_complete(ctx, tc, status, origin)
        code = @mark_complete_fn.call(ctx, tc, status, origin)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Returns a caller-owned copy of the finished run's result, or raises
      # HEGEL_E_NOT_COMPLETE (via LibHegel.check!) if the run has not
      # finished. The header documents this copy as staying valid after
      # #run_free, so +run+ can be freed as soon as this call returns; it
      # must be released separately, exactly once, with #run_result_free.
      def run_result(ctx, run)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @run_result_fn.call(ctx, run, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # No-op when +r+ is nil, matching hegel_run_result_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def run_result_free(ctx, r)
        @run_result_free_fn.call(ctx, r)
        nil
      end

      # Returns the raw hegel_run_status_t value (HEGEL_RUN_STATUS_PASSED /
      # _FAILED / _ERROR); this layer does not interpret it, matching how
      # #mark_complete passes hegel_status_t values through unexamined.
      def run_result_status(ctx, r)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
        code = @run_result_status_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_INT).unpack1("l")
      end

      # Returns nil when the run completed normally (PASSED or FAILED),
      # matching the header's documented NULL-on-success contract for this
      # out-parameter, distinct from an empty-string message. See
      # #nullable_out_string for the ownership note shared with
      # #failure_reproduction_blob.
      def run_result_error(ctx, r)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @run_result_error_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        nullable_out_string(out)
      end

      def run_result_failure_count(ctx, r)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
        code = @run_result_failure_count_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_SIZE_T).unpack1("J")
      end

      # +index+ must be less than #run_result_failure_count's value, per the
      # header. Returns a caller-owned failure handle, released separately
      # with #failure_free. Measured against libhegel 0.32.5: an
      # out-of-range +index+ comes back HEGEL_E_INVALID_ARG, even though
      # the header's Returns line for this call names only HEGEL_OK.
      def run_result_failure(ctx, r, index)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @run_result_failure_fn.call(ctx, r, index, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # No-op when +f+ is nil, matching hegel_failure_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def failure_free(ctx, f)
        @failure_free_fn.call(ctx, f)
        nil
      end

      # Copies the origin string out of libhegel's own buffer before
      # returning, since it is owned by the failure and only valid until
      # #failure_free.
      def failure_origin(ctx, f)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @failure_origin_fn.call(ctx, f, out)
        LibHegel.check!(self, ctx, code)
        out.ptr.to_s
      end

      # Returns nil when libhegel produced no reproduction blob for this
      # failure, matching the header's documented NULL-on-that-case
      # contract. See #nullable_out_string for the shared ownership note.
      def failure_reproduction_blob(ctx, f)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @failure_reproduction_blob_fn.call(ctx, f, out)
        LibHegel.check!(self, ctx, code)
        nullable_out_string(out)
      end

      # Replays +blob+ (from #failure_reproduction_blob) against +settings+
      # with no run handle and no run loop involved, per the header.
      # callback and user_data are always NULL here, for the same reason as
      # #run_start. +blob+ marshals as a pointer to its bytes for the const
      # char* argument, same as #settings_set_database. Raises
      # HEGEL_E_INVALID_ARG (via LibHegel.check!) for a blob that is
      # corrupt, non-UTF-8, or from an incompatible Hegel version;
      # HEGEL_E_STOP_TEST if the blob's choices no longer match the
      # caller's generators.
      def test_case_from_blob(ctx, settings, blob)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @test_case_from_blob_fn.call(ctx, settings, blob, nil, nil, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Forcing has to agree with +p+. Measured against libhegel 0.32.5:
      # forcing true at p = 0.0 and forcing false at p = 1.0 both come back
      # HEGEL_E_INVALID_ARG ("generate_boolean: cannot force ..."), while
      # forcing either way succeeds at any p between them. The header
      # describes the two ends as yielding false and true without consuming
      # entropy, and says nothing about what forcing does against them, so
      # this is written down where a caller constructing a forced draw will
      # look for it.
      def generate_boolean(ctx, tc, p, forced, has_forced)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_BOOL, Fiddle::RUBY_FREE)
        code = @generate_boolean_fn.call(ctx, tc, p, forced, has_forced, out)
        LibHegel.check!(self, ctx, code)
        out[0] != 0
      end

      def generate_integer(ctx, tc, min_value, max_value)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT64_T, Fiddle::RUBY_FREE)
        code = @generate_integer_fn.call(ctx, tc, min_value, max_value, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_INT64_T).unpack1("q")
      end

      private

      def bind(symbol, arg_types, ret_type)
        Fiddle::Function.new(@handle[symbol], arg_types, ret_type)
      end

      # Copies +out+'s const char* out-parameter into a Ruby String, or
      # returns nil if libhegel left it NULL. Shared by #run_result_error
      # and #failure_reproduction_blob, the two out-parameters the header
      # documents as nullable, so both branches only need to be exercised
      # once between the two call sites rather than at each one.
      def nullable_out_string(out)
        out.ptr.null? ? nil : out.ptr.to_s
      end
    end
  end
end
