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
        @settings_set_stateful_step_count_fn = bind(
          "hegel_settings_set_stateful_step_count",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT64_T],
          Fiddle::TYPE_INT
        )
        @settings_set_report_multiple_failures_fn = bind(
          "hegel_settings_set_report_multiple_failures",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_BOOL],
          Fiddle::TYPE_INT
        )
        @settings_set_database_key_fn = bind(
          "hegel_settings_set_database_key",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @settings_set_phases_fn = bind(
          "hegel_settings_set_phases",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
          Fiddle::TYPE_INT
        )
        @settings_set_suppress_health_check_fn = bind(
          "hegel_settings_set_suppress_health_check",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
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
        @target_fn = bind(
          "hegel_target",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_VOIDP],
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
        @generate_integer_big_fn = bind(
          "hegel_generate_integer_big",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP,
            Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @start_span_fn = bind(
          "hegel_start_span",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T],
          Fiddle::TYPE_INT
        )
        @stop_span_fn = bind(
          "hegel_stop_span",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_BOOL],
          Fiddle::TYPE_INT
        )

        @new_collection_fn = bind(
          "hegel_new_collection",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @collection_more_fn = bind(
          "hegel_collection_more",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @collection_reject_fn = bind(
          "hegel_collection_reject",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @collection_free_fn = bind("hegel_collection_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

        @new_pool_fn = bind(
          "hegel_new_pool",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @pool_add_fn = bind(
          "hegel_pool_add",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @pool_generate_fn = bind(
          "hegel_pool_generate",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_BOOL, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @pool_free_fn = bind("hegel_pool_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

        @new_state_machine_fn = bind(
          "hegel_new_state_machine",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP,
            Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @state_machine_next_rule_fn = bind(
          "hegel_state_machine_next_rule",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @state_machine_rule_rejected_fn = bind(
          "hegel_state_machine_rule_rejected",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @state_machine_free_fn = bind(
          "hegel_state_machine_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )

        @generate_float_fn = bind(
          "hegel_generate_float",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE,
            Fiddle::TYPE_BOOL, Fiddle::TYPE_BOOL, Fiddle::TYPE_BOOL, Fiddle::TYPE_BOOL, Fiddle::TYPE_DOUBLE,
            Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        # hegel_string_generator_text takes 14 arguments past ctx; the
        # last 8 (categories_len through exclude_characters_len) are the
        # category and explicit-character filter parameters this task
        # does not wire up (see #string_generator_text).
        @string_generator_text_fn = bind(
          "hegel_string_generator_text",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T,
            Fiddle::TYPE_UINT32_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T,
            Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @string_generator_free_fn = bind(
          "hegel_string_generator_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )
        @generate_string_fn = bind(
          "hegel_generate_string",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @generate_string_result_free_fn = bind(
          "hegel_generate_string_result_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )

        @generate_bytes_fn = bind(
          "hegel_generate_bytes",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @generate_bytes_result_free_fn = bind(
          "hegel_generate_bytes_result_free", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )

        @string_generator_regex_fn = bind(
          "hegel_string_generator_regex",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_BOOL, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @string_generator_email_fn = bind(
          "hegel_string_generator_email", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )
        @string_generator_url_fn = bind(
          "hegel_string_generator_url", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )
        @string_generator_domain_fn = bind(
          "hegel_string_generator_domain",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        @generate_ipv4_fn = bind(
          "hegel_generate_ipv4", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )
        @generate_ipv6_fn = bind(
          "hegel_generate_ipv6", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT
        )
        @generate_uuid_fn = bind(
          "hegel_generate_uuid",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT8_T, Fiddle::TYPE_BOOL, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        # hegel_generate_date / hegel_generate_time each take one struct by
        # value (hegel_date_t / hegel_time_t, 8 bytes of integers apiece);
        # hegel_generate_datetime takes two (hegel_datetime_t, a
        # hegel_date_t followed by a hegel_time_t, 16 bytes). Fiddle::Function
        # has no struct-by-value argument type -- Fiddle::CStruct and an
        # array of types both raise TypeError (measured on fiddle 1.1.8) --
        # so each is declared TYPE_UINT64_T instead: an 8-byte struct of
        # plain integers is exactly what arm64, System V, and Win64 all pass
        # in one general-purpose register, the same register a uint64
        # argument uses, so the packed bits produce the identical call.
        # #pack_date/#pack_time (and their inverses) below own that bit
        # layout, pinned against an independent computation in
        # test/hegel/test_lib_hegel.rb's own layout test; a size or offset
        # mismatch between the two is what that test exists to catch. See
        # docs/architecture.md, "Passing a struct by value".
        #
        # hegel_datetime_t's 16 bytes is where arm64/System V and Win64
        # diverge: the first two still pass it in two registers, which two
        # uint64 arguments reproduce (measured here, arm64-darwin), while
        # Win64 passes anything over 8 bytes by reference instead. Only the
        # two-register form is exercised on this host; CI's windows-latest
        # job is what confirms or refutes it for Win64, and a failure there
        # is a real finding, not a flake.
        @generate_date_fn = bind(
          "hegel_generate_date",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @generate_time_fn = bind(
          "hegel_generate_time",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        @generate_datetime_fn = bind(
          "hegel_generate_datetime",
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT64_T,
            Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
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

      def settings_set_stateful_step_count(ctx, s, n)
        code = @settings_set_stateful_step_count_fn.call(ctx, s, n)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_report_multiple_failures(ctx, s, yes)
        code = @settings_set_report_multiple_failures_fn.call(ctx, s, yes)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +key+ may be nil, which the header documents as clearing the key
      # (the default); a Ruby nil marshals to NULL for this TYPE_VOIDP
      # argument, the same as #settings_set_database's own nilable
      # database argument.
      def settings_set_database_key(ctx, s, key)
        code = @settings_set_database_key_fn.call(ctx, s, key)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +phases+ is a bitwise OR of the HEGEL_PHASE_* constants.
      def settings_set_phases(ctx, s, phases)
        code = @settings_set_phases_fn.call(ctx, s, phases)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +checks+ is a bitwise OR of the HEGEL_HC_* constants. Each call
      # overwrites the previous suppressions, per the header.
      def settings_set_suppress_health_check(ctx, s, checks)
        code = @settings_set_suppress_health_check_fn.call(ctx, s, checks)
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

      # Records a numeric observation under +label+ for libhegel's own
      # hill-climbing between generation rounds. The header documents this
      # as a no-op unless HEGEL_PHASE_TARGET is enabled (the default), and
      # a label as recordable at most once per test case; neither is
      # checked here, matching how this layer leaves every other
      # argument-shape rule to the engine's own HEGEL_E_INVALID_ARG.
      def target(ctx, tc, value, label)
        code = @target_fn.call(ctx, tc, value, label)
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
      # corrupt, non-UTF-8, or from an incompatible Hegel version.
      #
      # A blob whose choices no longer match the caller's generators is a
      # different case, and the header places it elsewhere: it "returns
      # HEGEL_E_STOP_TEST from the draw that overruns", so the replay is
      # built here and fails later, inside the body. Measured against
      # 0.32.5, replaying a two-draw blob against a five-draw body builds
      # fine and overruns at a draw.
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

      # hegel_generate_integer_big, for bounds that do not fit int64_t (see
      # Hegel::Generators::IntegerGenerator#do_draw, which dispatches here
      # instead of #generate_integer only when a bound is outside that
      # range). +min_value+/+max_value+ are encoded and the result decoded
      # via LibHegel.encode_integer_le/.decode_integer_le, which own the
      # two's-complement little-endian convention itself; this method only
      # owns the buffer marshalling around it. out_value's capacity is the
      # larger of the two encoded bounds, per the header's "out_value_cap >=
      # max(min_value_len, max_value_len) always succeeds"; the result is
      # read back at its own reported out_value_len, not the buffer's full
      # capacity, since decode_integer_le needs only that many bytes.
      def generate_integer_big(ctx, tc, min_value, max_value)
        min_bytes = LibHegel.encode_integer_le(min_value)
        max_bytes = LibHegel.encode_integer_le(max_value)
        min_value_ptr = bytes_to_pointer(min_bytes)
        max_value_ptr = bytes_to_pointer(max_bytes)

        cap = [min_bytes.bytesize, max_bytes.bytesize].max
        out_value = Fiddle::Pointer.malloc(cap, Fiddle::RUBY_FREE)
        out_value_len = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)

        code = @generate_integer_big_fn.call(
          ctx, tc, min_value_ptr, min_bytes.bytesize, max_value_ptr, max_bytes.bytesize, out_value, cap,
          out_value_len
        )
        LibHegel.check!(self, ctx, code)
        len = out_value_len.to_str(Fiddle::SIZEOF_SIZE_T).unpack1("J")
        LibHegel.decode_integer_le(out_value.to_str(len))
      end

      # Opens a span labelled +label+ (one of the HEGEL_LABEL_* constants,
      # or a caller-defined value that avoids them). Must be paired with
      # exactly one #stop_span call, per the header.
      def start_span(ctx, tc, label)
        code = @start_span_fn.call(ctx, tc, label)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Closes the most recently opened span. +discard+ true marks it
      # rejected, so libhegel retries from before the span opened.
      def stop_span(ctx, tc, discard)
        code = @stop_span_fn.call(ctx, tc, discard)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Returns a caller-owned collection handle, released separately
      # with #collection_free. Pass HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
      # as +max_size+ for no upper bound, per the header.
      def new_collection(ctx, tc, min_size, max_size)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @new_collection_fn.call(ctx, tc, min_size, max_size, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns whether libhegel wants another element; call in a loop,
      # drawing the next element each time this is true, until it is
      # false.
      def collection_more(ctx, tc, collection)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_BOOL, Fiddle::RUBY_FREE)
        code = @collection_more_fn.call(ctx, tc, collection, out)
        LibHegel.check!(self, ctx, code)
        out[0] != 0
      end

      # Tells libhegel the last element +collection+ produced is invalid.
      # +why+ is an optional human-readable reason (nil marshals to NULL,
      # which the header allows); the header documents it as validated
      # but reserved for future rejection diagnostics, unused today.
      def collection_reject(ctx, tc, collection, why = nil)
        code = @collection_reject_fn.call(ctx, tc, collection, why)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # No-op when +collection+ is nil, matching hegel_collection_free's
      # documented no-op-on-NULL contract; not translated, for the same
      # reason as #context_free. Unlike every other *_free above, this
      # call takes no test-case handle: the header documents a collection
      # as independent of the test case and run it was created under.
      def collection_free(ctx, collection)
        @collection_free_fn.call(ctx, collection)
        nil
      end

      # Returns a caller-owned pool handle, released separately with
      # #pool_free. A pool tracks a set of variable ids libhegel can draw
      # from and shrink over -- mostly used for stateful testing, where a
      # rule acts on a value a previous rule generated; the caller keeps
      # its own mapping from variable id to that value, per the header.
      def new_pool(ctx, tc)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @new_pool_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns a fresh variable id for the caller to associate with the
      # value it just generated. The header documents the id as drawn
      # from +tc+'s stream and recorded by value, not by pool position, so
      # it stays stable across shrinking: deleting an earlier addition
      # never renumbers the survivors.
      def pool_add(ctx, tc, pool)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT64_T, Fiddle::RUBY_FREE)
        code = @pool_add_fn.call(ctx, tc, pool, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_INT64_T).unpack1("q")
      end

      # Returns a variable id libhegel chose from +pool+ (and can shrink
      # which one it chose). +consume+ true removes the drawn variable
      # from the pool; false leaves it. LibHegel.check! already translates
      # HEGEL_E_ASSUME -- what the header documents this call returning
      # when +pool+ holds no variables -- to Hegel::AssumeFailed, the same
      # translation every other assumption failure gets, so no extra code
      # is needed here for that case; pinned by
      # test_real_pool_generate_on_an_empty_pool_raises_assume_failed in
      # test/hegel/test_lib_hegel.rb.
      def pool_generate(ctx, tc, pool, consume)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT64_T, Fiddle::RUBY_FREE)
        code = @pool_generate_fn.call(ctx, tc, pool, consume, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_INT64_T).unpack1("q")
      end

      # No-op when +pool+ is nil, matching hegel_pool_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def pool_free(ctx, pool)
        @pool_free_fn.call(ctx, pool)
        nil
      end

      # Returns a caller-owned state-machine handle, released separately
      # with #state_machine_free. +rule_names+ and +invariant_names+ are
      # each an Array of Ruby Strings, packed into the const char *const *
      # arguments hegel_new_state_machine expects by #pack_name_array; see
      # that method's own comment for how and why. Validating
      # +rule_names+ as non-empty (the header's own requirement) is left
      # to the caller, the same division of labor #new_collection leaves
      # to the caller for its own min_size/max_size ordering.
      def new_state_machine(ctx, tc, rule_names, invariant_names)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        # _rule_pointers / _invariant_pointers are unread past the call
        # below, the same shape #generate_integer_big's own
        # min_value_ptr/max_value_ptr already have; keeping them as local
        # variables here, not discarded inside #pack_name_array, is what
        # keeps them -- and the Strings they point into -- live through
        # the call. The leading underscore tells the linter that on
        # purpose, the same way it would for a block argument the block
        # never reads.
        rule_names_ptr, _rule_pointers = pack_name_array(rule_names)
        invariant_names_ptr, _invariant_pointers = pack_name_array(invariant_names)

        code = @new_state_machine_fn.call(
          ctx, tc, rule_names_ptr, rule_names.size, invariant_names_ptr, invariant_names.size, out
        )
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns the index (in 0...num_rules) of the next stateful-testing
      # rule to run, or HEGEL_STATE_MACHINE_DONE (-1) once +state_machine+'s
      # step budget is exhausted -- returned as the raw sentinel value, not
      # translated to nil. Unlike #next_test_case's out-parameter, which is
      # NULL (no value) at the equivalent boundary, the header documents
      # this out-parameter as holding a real value, -1, at that point; a
      # caller comparing against HEGEL_STATE_MACHINE_DONE is the layer that
      # should decide what that value means, the same way #run_result_status
      # hands back its raw HEGEL_RUN_STATUS_* value unexamined.
      def state_machine_next_rule(ctx, tc, state_machine)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT64_T, Fiddle::RUBY_FREE)
        code = @state_machine_next_rule_fn.call(ctx, tc, state_machine, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_INT64_T).unpack1("q")
      end

      # Reports the rule most recently returned by #state_machine_next_rule
      # as rejected (an assumption failed before it completed), so it does
      # not count toward the step budget. Raises HEGEL_E_INVALID_ARG (via
      # LibHegel.check!, translated to Hegel::Error) when no rule is
      # outstanding, per the header.
      def state_machine_rule_rejected(ctx, tc, state_machine)
        code = @state_machine_rule_rejected_fn.call(ctx, tc, state_machine)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # No-op when +state_machine+ is nil, matching
      # hegel_state_machine_free's documented no-op-on-NULL contract; not
      # translated, for the same reason as #context_free.
      def state_machine_free(ctx, state_machine)
        @state_machine_free_fn.call(ctx, state_machine)
        nil
      end

      # Returns a drawn double. +smallest_nonzero_magnitude+ must be
      # positive and finite; pass
      # HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED for width
      # 64 with no restriction, per the header.
      def generate_float(ctx, tc, width, min_value, max_value, allow_nan, allow_infinity, exclude_min, exclude_max,
        smallest_nonzero_magnitude)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_DOUBLE, Fiddle::RUBY_FREE)
        code = @generate_float_fn.call(ctx, tc, width, min_value, max_value, allow_nan, allow_infinity, exclude_min,
          exclude_max, smallest_nonzero_magnitude, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(Fiddle::SIZEOF_DOUBLE).unpack1("D")
      end

      # Returns a caller-owned string generator handle, released
      # separately with #string_generator_free (or scoped with
      # Hegel::TestCase#with_text_generator). +categories+,
      # +exclude_categories+, +include_characters+, and
      # +exclude_characters+ are always passed as NULL/0 below: this call
      # only wires up the codepoint-range constraints of the 14-argument
      # bind; the category and explicit-character filter arguments are a
      # later generator's scope, layered on top of this same bind.
      def string_generator_text(ctx, min_size:, max_size:, codec: nil, min_codepoint: 0, max_codepoint: 0xFFFFFFFF)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @string_generator_text_fn.call(
          ctx, min_size, max_size, codec, min_codepoint, max_codepoint,
          nil, 0, nil, 0, nil, 0, nil, 0,
          out
        )
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # No-op when +generator+ is nil, matching
      # hegel_string_generator_free's documented no-op-on-NULL contract;
      # not translated, for the same reason as #context_free.
      def string_generator_free(ctx, generator)
        @string_generator_free_fn.call(ctx, generator)
        nil
      end

      # Returns a drawn String, force-encoded as UTF-8 (this codec's
      # alphabet), copying exactly the returned +len+ bytes rather than
      # treating the buffer as a C string: the header documents it as not
      # NUL-terminated and possibly containing interior NUL bytes, since
      # the drawn alphabet can include U+0000.
      #
      # The native buffer is released in +ensure+ via
      # #generate_string_result_free, called directly from here rather
      # than left to the caller: nothing outside this file may hold or
      # read the raw struct (Fiddle is confined to this file), so unlike
      # #new_collection or #string_generator_text, the freeable handle
      # here never leaves this method. Freeing is safe even when the draw
      # above raised: +out+ starts zero-filled (Fiddle::Pointer.malloc
      # calloc's its memory) and libhegel only writes into it on success,
      # so the struct #generate_string_result_free sees here is always
      # either a completed draw or the all-zero state the header
      # documents as already safe to free.
      def generate_string(ctx, tc, generator)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP + Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
        code = @generate_string_fn.call(ctx, tc, generator, out)
        LibHegel.check!(self, ctx, code)
        len = out[Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_SIZE_T].unpack1("J")
        out.ptr.to_str(len).force_encoding(Encoding::UTF_8)
      ensure
        generate_string_result_free(ctx, out)
      end

      # No-op when +result+ is nil, matching
      # hegel_generate_string_result_free's documented no-op-on-NULL
      # contract (also safe on an already-freed, zeroed struct); not
      # translated, for the same reason as #context_free.
      def generate_string_result_free(ctx, result)
        @generate_string_result_free_fn.call(ctx, result)
        nil
      end

      # Returns drawn bytes as a String, read via +len+ the same way
      # #generate_string reads its own out-parameter: the header gives no
      # NUL-termination guarantee for this buffer either, so the length is
      # what makes the copy exact.
      #
      # Unlike #generate_string, the result is never force-encoded.
      # hegel_generate_bytes_result_t is documented as a byte buffer, not
      # text, and Fiddle::Pointer#to_str already returns ASCII-8BIT
      # (Encoding::BINARY), which is the encoding a byte string belongs in.
      #
      # The native buffer is released in +ensure+ via
      # #generate_bytes_result_free, for the same reason #generate_string
      # frees its own result from inside this file: Fiddle is confined to
      # this file, so the freeable handle never leaves this method. Freeing
      # is safe even when the draw above raised, for the same
      # zero-filled-malloc reason documented on #generate_string: the
      # header documents hegel_generate_bytes_result_free as safe on an
      # already-freed (zeroed) struct too.
      def generate_bytes(ctx, tc, min_size, max_size)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP + Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
        code = @generate_bytes_fn.call(ctx, tc, min_size, max_size, out)
        LibHegel.check!(self, ctx, code)
        len = out[Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_SIZE_T].unpack1("J")
        out.ptr.to_str(len)
      ensure
        generate_bytes_result_free(ctx, out)
      end

      # No-op when +result+ is nil, matching
      # hegel_generate_bytes_result_free's documented no-op-on-NULL
      # contract (also safe on an already-freed, zeroed struct); not
      # translated, for the same reason as #context_free.
      def generate_bytes_result_free(ctx, result)
        @generate_bytes_result_free_fn.call(ctx, result)
        nil
      end

      # Returns a caller-owned string generator handle matching +pattern+
      # (Python re syntax), released the same way as #string_generator_text:
      # with #string_generator_free. +alphabet+ is an optional string
      # generator handle (built via #string_generator_text, scoped with
      # Hegel::TestCase#with_text_generator) whose character set constrains the
      # padding and wildcard characters; nil (the default) marshals to NULL,
      # the header's documented "no particular alphabet" case.
      def string_generator_regex(ctx, pattern, fullmatch, alphabet = nil)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @string_generator_regex_fn.call(ctx, pattern, fullmatch, alphabet, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns a caller-owned string generator handle producing RFC
      # 5321/5322 email addresses, released the same way as
      # #string_generator_text.
      def string_generator_email(ctx)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @string_generator_email_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns a caller-owned string generator handle producing RFC 3986
      # http/https URLs, released the same way as #string_generator_text.
      def string_generator_url(ctx)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @string_generator_url_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # Returns a caller-owned string generator handle producing
      # fully-qualified domain names, released the same way as
      # #string_generator_text. +max_length+ is the total FQDN length; the
      # header documents it as valid in 4..=255. This layer does not
      # validate that range itself, only translates the
      # HEGEL_E_INVALID_ARG the engine returns outside it, the same
      # division of labor #settings_set_database and every other setter
      # above already follows.
      def string_generator_domain(ctx, max_length)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @string_generator_domain_fn.call(ctx, max_length, out)
        LibHegel.check!(self, ctx, code)
        out.ptr
      end

      # hegel_generate_ipv4 writes into a caller-supplied fixed-length
      # buffer instead of handing back a pointer through an out-parameter,
      # unlike every generate_* call above: the header documents out_bytes
      # as the address's 4 network-order bytes with no separate length to
      # read, so the buffer's own size is the contract instead of a
      # trailing len field. IPAddr conversion is left to the generator
      # built on top of this call; this layer returns the raw bytes.
      def generate_ipv4(ctx, tc)
        out = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        code = @generate_ipv4_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(4)
      end

      # Same fixed-buffer shape as #generate_ipv4, sized for the header's
      # documented 16 network-order bytes.
      def generate_ipv6(ctx, tc)
        out = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
        code = @generate_ipv6_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(16)
      end

      # hegel_generate_uuid, returning the drawn UUID's 16 raw bytes.
      # +has_version+ true forces the RFC 4122 version nibble to +version+
      # (0..15) and the variant nibble to the RFC 4122 variant, per the
      # header; +version+ is ignored (but still marshalled; pass 0) when
      # +has_version+ is false. Converting the raw bytes to the standard
      # 8-4-4-4-12 hex String is left to Hegel::Generators::UuidsGenerator,
      # the same division of labor #generate_ipv4/#generate_ipv6 already
      # follow for their own byte-to-address conversion. An out-of-range
      # +version+ is not checked here: measured against libhegel 0.32.5, the
      # engine itself returns HEGEL_E_INVALID_ARG for one, which
      # LibHegel.check! already translates.
      def generate_uuid(ctx, tc, version, has_version)
        out = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
        code = @generate_uuid_fn.call(ctx, tc, version, has_version, out)
        LibHegel.check!(self, ctx, code)
        out.to_str(16)
      end

      # hegel_generate_date. +min_value+/+max_value+ are each a
      # [year, month, day] Array, packed by #pack_date into the uint64
      # #@generate_date_fn's struct-by-value argument actually is (see the
      # comment above that bind call). Returns a [year, month, day] Array,
      # the field-level shape Hegel::Generators::DatesGenerator builds its
      # own Date from -- the same division of labor #generate_ipv4/
      # #generate_uuid already follow, returning raw values for a generator
      # one layer up to turn into the caller-facing type. This layer does
      # not validate year/month/day itself: measured against libhegel
      # 0.32.5, an invalid date (month 13, say) already comes back
      # HEGEL_E_INVALID_ARG, translated by LibHegel.check! below, even
      # though the header's Returns line for this call names only
      # HEGEL_OK/HEGEL_E_STOP_TEST -- the same gap #run_result_failure's own
      # comment already notes for a different call.
      def generate_date(ctx, tc, min_value, max_value)
        out = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        code = @generate_date_fn.call(ctx, tc, pack_date(min_value), pack_date(max_value), out)
        LibHegel.check!(self, ctx, code)
        unpack_date(out.to_str(8))
      end

      # hegel_generate_time. +min_value+/+max_value+ are each an
      # [hour, minute, second, microsecond] Array; same packing, return
      # shape, and validation division of labor as #generate_date above,
      # for Hegel::Generators::TimesGenerator.
      def generate_time(ctx, tc, min_value, max_value)
        out = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        code = @generate_time_fn.call(ctx, tc, pack_time(min_value), pack_time(max_value), out)
        LibHegel.check!(self, ctx, code)
        unpack_time(out.to_str(8))
      end

      # hegel_generate_datetime. +min_date+/+max_date+ are each a
      # [year, month, day] Array; +min_time+/+max_time+ are each an
      # [hour, minute, second, microsecond] Array -- hegel_datetime_t is a
      # hegel_date_t followed by a hegel_time_t (see the comment above
      # #@generate_datetime_fn's bind call for the two-register packing
      # this call needs on top of #generate_date/#generate_time's own
      # one-register form). Returns a
      # [[year, month, day], [hour, minute, second, microsecond]] pair, for
      # Hegel::Generators::DatetimesGenerator to build its own Time from.
      def generate_datetime(ctx, tc, min_date, min_time, max_date, max_time)
        out = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
        code = @generate_datetime_fn.call(
          ctx, tc, pack_date(min_date), pack_time(min_time), pack_date(max_date), pack_time(max_time), out
        )
        LibHegel.check!(self, ctx, code)
        bytes = out.to_str(16)
        [unpack_date(bytes[0, 8]), unpack_time(bytes[8, 8])]
      end

      private

      # Copies +bytes+ into a freshly malloc'd buffer, for
      # #generate_integer_big's min_value/max_value: a const uint8_t*
      # argument libhegel reads from, the opposite direction of an
      # out-parameter buffer (which libhegel writes into, and the caller
      # then reads).
      def bytes_to_pointer(bytes)
        ptr = Fiddle::Pointer.malloc(bytes.bytesize, Fiddle::RUBY_FREE)
        ptr[0, bytes.bytesize] = bytes
        ptr
      end

      # Packs +names+ (an Array of Ruby Strings) into a const char *const *
      # for #new_state_machine's rule_names/invariant_names arguments: one
      # address per name, in a single buffer, addresses read via
      # Fiddle::Pointer.to_ptr(name) and packed with "J" (Fiddle's pack
      # code for uintptr_t). Each String is already NUL-terminated in its
      # own underlying buffer -- Ruby keeps that true of every String, for
      # exactly this kind of C interop -- so no separate NUL-terminated
      # copy is built here.
      #
      # Returns [pointer, kept_alive]. The memory those addresses point at
      # belongs to the Strings, and the packed buffer is a copy of the
      # addresses alone, so something has to hold the Strings until the
      # native call reads them. Two things do. The caller's own +names+
      # argument is a live local for the length of that call, and each
      # Fiddle::Pointer that Fiddle::Pointer.to_ptr returns holds a
      # reference to the String it was built from -- measured on fiddle
      # 1.1.8 via ObjectSpace.reachable_objects_from, and pinned by a test
      # in test/hegel/test_lib_hegel.rb, because the whole point of
      # +kept_alive+ rests on it and a fiddle that stopped doing it would
      # otherwise surface as an occasional crash rather than a failure.
      #
      # Empty +names+ maps to [nil, []] -- NULL and (by the caller passing
      # names.size, 0) the header's own contract for invariant_names' "no
      # invariants" case. #new_state_machine reuses this same packing for
      # rule_names too, whose own documented non-empty requirement this
      # method does not enforce; that validation belongs one layer up, in
      # a caller that can raise Hegel::Error with a message naming the
      # factory method, not in a method whose only job is packing an
      # Array into a buffer.
      def pack_name_array(names)
        return [nil, []] if names.empty?

        pointers = names.map { |name| Fiddle::Pointer.to_ptr(name) }
        addresses = pointers.map(&:to_i).pack("J*")
        [bytes_to_pointer(addresses), pointers]
      end

      def bind(symbol, arg_types, ret_type)
        Fiddle::Function.new(@handle[symbol], arg_types, ret_type)
      end

      # hegel_date_t: { int32_t year; uint8_t month; uint8_t day; }. The
      # compiler pads this to 8 bytes to keep the struct's own 4-byte
      # alignment (from its int32_t member), leaving 2 unused bytes after
      # +day+ -- this packs only the 6 bytes the struct actually reads, and
      # leaves the padding bits zero, which is safe because nothing reads
      # padding. year's bit range is masked to 32 bits first so a negative
      # Ruby Integer contributes its two's-complement low 32 bits, the same
      # bits an int32_t holding that value would have. Offsets (year 0,
      # month 4, day 5) are asserted independently of this bit math in
      # test/hegel/test_lib_hegel.rb's own layout test.
      def pack_date(date)
        year, month, day = date
        (year & 0xFFFFFFFF) | (month << 32) | (day << 40)
      end

      # The inverse of #pack_date, reading the 8-byte out-parameter
      # #generate_date fills in. "l" (lowercase) unpacks a signed 32-bit
      # int, matching hegel_date_t's own int32_t year -- unlike
      # #generate_integer's out-parameter (an 8-byte int64_t, unpacked
      # "q"), this one is 4 bytes.
      def unpack_date(bytes)
        year = bytes[0, 4].unpack1("l")
        month = bytes.getbyte(4)
        day = bytes.getbyte(5)
        [year, month, day]
      end

      # hegel_time_t: { uint8_t hour, minute, second; uint32_t
      # microsecond; }. Padded to 8 bytes the same way hegel_date_t is (2
      # unused bytes after +second+, to align +microsecond+ to 4 bytes);
      # see #pack_date's own comment. Offsets (hour 0, minute 1, second 2,
      # microsecond 4) are asserted the same way #pack_date's are.
      def pack_time(time)
        hour, minute, second, microsecond = time
        hour | (minute << 8) | (second << 16) | (microsecond << 32)
      end

      # The inverse of #pack_time. "L" (uppercase) unpacks an unsigned
      # 32-bit int, matching hegel_time_t's own uint32_t microsecond.
      def unpack_time(bytes)
        hour = bytes.getbyte(0)
        minute = bytes.getbyte(1)
        second = bytes.getbyte(2)
        microsecond = bytes[4, 4].unpack1("L")
        [hour, minute, second, microsecond]
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
