# frozen_string_literal: true

require "ffi"
require_relative "../lib_hegel"

module Hegel
  module LibHegel
    # Drives libhegel's C ABI through the ffi gem. Every other file works
    # against the plain Ruby values and method calls this class exposes, so
    # a future change to how the native call happens has exactly one file to
    # change.
    #
    # Opens the library and binds every function once, in #initialize, each
    # as its own FFI::Function held in an instance variable (see
    # #initialize's own comment for why this binds one callable per function
    # rather than attach_function's usual class-body DSL). Each call below
    # reuses that already-bound function rather than re-resolving the
    # symbol.
    class Real
      # hegel_date_t / hegel_time_t / hegel_datetime_t, transcribed field
      # for field from hegel-c/include/hegel.h. FFI::Struct computes each
      # field's offset and the struct's own alignment padding from this
      # layout -- the same C-ABI rules the compiled library was built
      # against -- so there is no hand-computed byte offset here to drift
      # from the header. Declared with .by_value in #initialize's own
      # #bind calls, so a call marshals the whole struct rather than a
      # pointer to it, including on an ABI that passes a struct this size
      # by hidden reference instead of in registers: classifying that is
      # libffi's own job once .by_value asks for it. See docs/adr/0013 for
      # the degenerate-draw check this layout is measured against.
      class DateStruct < FFI::Struct
        layout :year, :int32, :month, :uint8, :day, :uint8
      end

      class TimeStruct < FFI::Struct
        layout :hour, :uint8, :minute, :uint8, :second, :uint8, :microsecond, :uint32
      end

      class DatetimeStruct < FFI::Struct
        layout :date, DateStruct, :time, TimeStruct
      end

      # hegel_generate_string_result_t and hegel_generate_bytes_result_t are
      # both `{ char *data; size_t len; }` in hegel-c/include/hegel.h --
      # byte-for-byte the same layout under two names, one per element type
      # the two calls draw. One Ruby struct mirrors both; #generate_string
      # and #generate_bytes each pass a fresh instance as the out-parameter
      # and read it back through their own method below.
      class RawResultStruct < FFI::Struct
        layout :data, :pointer, :len, :size_t
      end

      private_constant :DateStruct, :TimeStruct, :DatetimeStruct, :RawResultStruct

      # Opens +path+ (default: Hegel::Locate.resolve) and binds the
      # functions this boundary calls. Immediately after, opens a context
      # of its own to compare the loaded engine's version against
      # Hegel::LIBHEGEL_VERSION, warning on +io+ (default $stderr) on a
      # mismatch; see LibHegel.warn_on_version_mismatch. +io+ exists so a
      # test can capture the warning instead of writing to the real stderr.
      #
      # attach_function's usual DSL binds a fixed library, named at
      # class-definition time, to methods it defines on a class or module
      # body. This class instead takes +path+ as a constructor argument,
      # resolved fresh per instance, so attach_function's own per-instance
      # form is an anonymous module built fresh in #initialize -- measured
      # against a realistic property run on this project's own machine,
      # that form was consistently slower, call for call, than binding
      # each function directly off a resolved symbol, the way #bind below
      # does it: FFI::DynamicLibrary.open gives a handle to resolve
      # symbols against, and each call to #bind wraps one resolved symbol
      # as a callable FFI::Function, stored in its own instance variable
      # and invoked with #call by the method below it.
      def initialize(path = Hegel::Locate.resolve, io: $stderr)
        @handle = FFI::DynamicLibrary.open(path, FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_GLOBAL)

        @hegel_context_new_fn = bind("hegel_context_new", [], :pointer)
        @hegel_context_free_fn = bind("hegel_context_free", [:pointer], :int32)
        @hegel_context_last_error_fn = bind("hegel_context_last_error", [:pointer], :pointer)
        @hegel_version_fn = bind("hegel_version", [:pointer, :pointer], :int32)

        @hegel_settings_new_fn = bind("hegel_settings_new", [:pointer, :pointer], :int32)
        @hegel_settings_free_fn = bind("hegel_settings_free", [:pointer, :pointer], :int32)
        @hegel_settings_set_test_cases_fn = bind(
          "hegel_settings_set_test_cases", [:pointer, :pointer, :uint64], :int32
        )
        @hegel_settings_set_verbosity_fn = bind(
          "hegel_settings_set_verbosity", [:pointer, :pointer, :uint32], :int32
        )
        @hegel_settings_set_seed_fn = bind(
          "hegel_settings_set_seed", [:pointer, :pointer, :uint64, :bool], :int32
        )
        @hegel_settings_set_derandomize_fn = bind(
          "hegel_settings_set_derandomize", [:pointer, :pointer, :bool], :int32
        )
        @hegel_settings_set_database_fn = bind(
          "hegel_settings_set_database", [:pointer, :pointer, :string], :int32
        )
        @hegel_settings_set_stateful_step_count_fn = bind(
          "hegel_settings_set_stateful_step_count", [:pointer, :pointer, :int64], :int32
        )
        @hegel_settings_set_report_multiple_failures_fn = bind(
          "hegel_settings_set_report_multiple_failures", [:pointer, :pointer, :bool], :int32
        )
        @hegel_settings_set_database_key_fn = bind(
          "hegel_settings_set_database_key", [:pointer, :pointer, :string], :int32
        )
        @hegel_settings_set_phases_fn = bind(
          "hegel_settings_set_phases", [:pointer, :pointer, :uint32], :int32
        )
        @hegel_settings_set_suppress_health_check_fn = bind(
          "hegel_settings_set_suppress_health_check", [:pointer, :pointer, :uint32], :int32
        )

        @hegel_run_start_fn = bind(
          "hegel_run_start", [:pointer, :pointer, :pointer, :pointer, :pointer], :int32
        )
        @hegel_next_test_case_fn = bind("hegel_next_test_case", [:pointer, :pointer, :pointer], :int32)
        @hegel_run_free_fn = bind("hegel_run_free", [:pointer, :pointer], :int32)
        @hegel_test_case_free_fn = bind("hegel_test_case_free", [:pointer, :pointer], :int32)
        @hegel_mark_complete_fn = bind("hegel_mark_complete", [:pointer, :pointer, :uint32, :string], :int32)
        @hegel_target_fn = bind("hegel_target", [:pointer, :pointer, :double, :string], :int32)

        @hegel_run_result_fn = bind("hegel_run_result", [:pointer, :pointer, :pointer], :int32)
        @hegel_run_result_free_fn = bind("hegel_run_result_free", [:pointer, :pointer], :int32)
        @hegel_run_result_status_fn = bind("hegel_run_result_status", [:pointer, :pointer, :pointer], :int32)
        @hegel_run_result_error_fn = bind("hegel_run_result_error", [:pointer, :pointer, :pointer], :int32)
        @hegel_run_result_failure_count_fn = bind(
          "hegel_run_result_failure_count", [:pointer, :pointer, :pointer], :int32
        )
        @hegel_run_result_failure_fn = bind(
          "hegel_run_result_failure", [:pointer, :pointer, :size_t, :pointer], :int32
        )
        @hegel_failure_free_fn = bind("hegel_failure_free", [:pointer, :pointer], :int32)
        @hegel_failure_origin_fn = bind("hegel_failure_origin", [:pointer, :pointer, :pointer], :int32)
        @hegel_failure_reproduction_blob_fn = bind(
          "hegel_failure_reproduction_blob", [:pointer, :pointer, :pointer], :int32
        )
        @hegel_test_case_from_blob_fn = bind(
          "hegel_test_case_from_blob", [:pointer, :pointer, :string, :pointer, :pointer, :pointer], :int32
        )

        @hegel_generate_boolean_fn = bind(
          "hegel_generate_boolean", [:pointer, :pointer, :double, :bool, :bool, :pointer], :int32
        )
        @hegel_generate_integer_fn = bind(
          "hegel_generate_integer", [:pointer, :pointer, :int64, :int64, :pointer], :int32
        )
        @hegel_generate_integer_big_fn = bind(
          "hegel_generate_integer_big",
          [:pointer, :pointer, :pointer, :size_t, :pointer, :size_t, :pointer, :size_t, :pointer], :int32
        )

        @hegel_start_span_fn = bind("hegel_start_span", [:pointer, :pointer, :uint64], :int32)
        @hegel_stop_span_fn = bind("hegel_stop_span", [:pointer, :pointer, :bool], :int32)

        @hegel_new_collection_fn = bind(
          "hegel_new_collection", [:pointer, :pointer, :uint64, :uint64, :pointer], :int32
        )
        @hegel_collection_more_fn = bind("hegel_collection_more", [:pointer, :pointer, :pointer, :pointer], :int32)
        @hegel_collection_reject_fn = bind(
          "hegel_collection_reject", [:pointer, :pointer, :pointer, :string], :int32
        )
        @hegel_collection_free_fn = bind("hegel_collection_free", [:pointer, :pointer], :int32)

        @hegel_new_pool_fn = bind("hegel_new_pool", [:pointer, :pointer, :pointer], :int32)
        @hegel_pool_add_fn = bind("hegel_pool_add", [:pointer, :pointer, :pointer, :pointer], :int32)
        @hegel_pool_generate_fn = bind(
          "hegel_pool_generate", [:pointer, :pointer, :pointer, :bool, :pointer], :int32
        )
        @hegel_pool_free_fn = bind("hegel_pool_free", [:pointer, :pointer], :int32)

        @hegel_new_state_machine_fn = bind(
          "hegel_new_state_machine",
          [:pointer, :pointer, :pointer, :size_t, :pointer, :size_t, :pointer], :int32
        )
        @hegel_state_machine_next_rule_fn = bind(
          "hegel_state_machine_next_rule", [:pointer, :pointer, :pointer, :pointer], :int32
        )
        @hegel_state_machine_rule_rejected_fn = bind(
          "hegel_state_machine_rule_rejected", [:pointer, :pointer, :pointer], :int32
        )
        @hegel_state_machine_free_fn = bind("hegel_state_machine_free", [:pointer, :pointer], :int32)

        @hegel_generate_float_fn = bind(
          "hegel_generate_float",
          [:pointer, :pointer, :uint32, :double, :double, :bool, :bool, :bool, :bool, :double, :pointer], :int32
        )

        # hegel_string_generator_text takes 14 arguments past ctx; the
        # last 8 (categories_len through exclude_characters_len) are the
        # category and explicit-character filter parameters this task
        # does not wire up (see #string_generator_text).
        @hegel_string_generator_text_fn = bind(
          "hegel_string_generator_text",
          [:pointer, :uint64, :uint64, :string, :uint32, :uint32,
            :pointer, :size_t, :pointer, :size_t, :pointer, :size_t, :pointer, :size_t,
            :pointer],
          :int32
        )
        @hegel_string_generator_free_fn = bind("hegel_string_generator_free", [:pointer, :pointer], :int32)
        @hegel_generate_string_fn = bind(
          "hegel_generate_string", [:pointer, :pointer, :pointer, :pointer], :int32
        )
        @hegel_generate_string_result_free_fn = bind(
          "hegel_generate_string_result_free", [:pointer, :pointer], :int32
        )

        @hegel_generate_bytes_fn = bind(
          "hegel_generate_bytes", [:pointer, :pointer, :uint64, :uint64, :pointer], :int32
        )
        @hegel_generate_bytes_result_free_fn = bind(
          "hegel_generate_bytes_result_free", [:pointer, :pointer], :int32
        )

        @hegel_string_generator_regex_fn = bind(
          "hegel_string_generator_regex", [:pointer, :string, :bool, :pointer, :pointer], :int32
        )
        @hegel_string_generator_email_fn = bind("hegel_string_generator_email", [:pointer, :pointer], :int32)
        @hegel_string_generator_url_fn = bind("hegel_string_generator_url", [:pointer, :pointer], :int32)
        @hegel_string_generator_domain_fn = bind(
          "hegel_string_generator_domain", [:pointer, :uint64, :pointer], :int32
        )

        @hegel_generate_ipv4_fn = bind("hegel_generate_ipv4", [:pointer, :pointer, :pointer], :int32)
        @hegel_generate_ipv6_fn = bind("hegel_generate_ipv6", [:pointer, :pointer, :pointer], :int32)
        @hegel_generate_uuid_fn = bind(
          "hegel_generate_uuid", [:pointer, :pointer, :uint8, :bool, :pointer], :int32
        )

        @hegel_generate_date_fn = bind(
          "hegel_generate_date", [:pointer, :pointer, DateStruct.by_value, DateStruct.by_value, :pointer], :int32
        )
        @hegel_generate_time_fn = bind(
          "hegel_generate_time", [:pointer, :pointer, TimeStruct.by_value, TimeStruct.by_value, :pointer], :int32
        )
        @hegel_generate_datetime_fn = bind(
          "hegel_generate_datetime",
          [:pointer, :pointer, DatetimeStruct.by_value, DatetimeStruct.by_value, :pointer], :int32
        )

        LibHegel.with_context(self) { |ctx| LibHegel.warn_on_version_mismatch(self, ctx, io: io) }
      end

      # hegel_context_new never returns NULL (guaranteed by the header), so
      # the handle returned here is always live.
      def context_new
        @hegel_context_new_fn.call
      end

      # No-op when +ctx+ is nil: libhegel documents hegel_context_free as a
      # no-op on NULL, and a Ruby nil marshals to a NULL pointer for a
      # :pointer argument here, so no separate nil check is needed on this
      # side. The result code is not translated: the header documents this
      # call as always returning HEGEL_OK, so there is nothing to raise.
      def context_free(ctx)
        @hegel_context_free_fn.call(ctx)
        nil
      end

      # Copies the message out of libhegel's own buffer into a Ruby String
      # before returning, since the header documents that buffer as
      # borrowed and invalidated by the next call taking the same context.
      def context_last_error(ctx)
        @hegel_context_last_error_fn.call(ctx).read_string
      end

      # Returns the loaded engine's version string, or raises the
      # exception LibHegel.check! translates this call's result code to.
      def version(ctx)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_version_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer.read_string
      end

      # Returns a settings handle initialized with libhegel's defaults, or
      # raises the exception LibHegel.check! translates this call's result
      # code to.
      def settings_new(ctx)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_settings_new_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # No-op when +s+ is nil, matching hegel_settings_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free: the header documents this call as always returning
      # HEGEL_OK.
      def settings_free(ctx, s)
        @hegel_settings_free_fn.call(ctx, s)
        nil
      end

      def settings_set_test_cases(ctx, s, n)
        code = @hegel_settings_set_test_cases_fn.call(ctx, s, n)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_verbosity(ctx, s, v)
        code = @hegel_settings_set_verbosity_fn.call(ctx, s, v)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_seed(ctx, s, seed, has_seed)
        code = @hegel_settings_set_seed_fn.call(ctx, s, seed, has_seed)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_derandomize(ctx, s, derandomize)
        code = @hegel_settings_set_derandomize_fn.call(ctx, s, derandomize)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +database+ may be nil (libhegel's own default path) or a String,
      # including "" to disable the database. Declared :string below, so a
      # Ruby String marshals as a const char* to its bytes and nil marshals
      # to NULL, both directly -- no separate pointer to build here.
      def settings_set_database(ctx, s, database)
        code = @hegel_settings_set_database_fn.call(ctx, s, database)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_stateful_step_count(ctx, s, n)
        code = @hegel_settings_set_stateful_step_count_fn.call(ctx, s, n)
        LibHegel.check!(self, ctx, code)
        nil
      end

      def settings_set_report_multiple_failures(ctx, s, yes)
        code = @hegel_settings_set_report_multiple_failures_fn.call(ctx, s, yes)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +key+ may be nil, which the header documents as clearing the key
      # (the default); nil marshals to NULL for this :string argument, the
      # same as #settings_set_database's own nilable database argument.
      def settings_set_database_key(ctx, s, key)
        code = @hegel_settings_set_database_key_fn.call(ctx, s, key)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +phases+ is a bitwise OR of the HEGEL_PHASE_* constants.
      def settings_set_phases(ctx, s, phases)
        code = @hegel_settings_set_phases_fn.call(ctx, s, phases)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +checks+ is a bitwise OR of the HEGEL_HC_* constants. Each call
      # overwrites the previous suppressions, per the header.
      def settings_set_suppress_health_check(ctx, s, checks)
        code = @hegel_settings_set_suppress_health_check_fn.call(ctx, s, checks)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # +settings+ can be freed by the caller as soon as this call returns:
      # the header documents that hegel_run_start copies the settings it is
      # given rather than borrowing them. callback and user_data are always
      # NULL here, which the header documents as leaving libhegel's output
      # on stderr; wiring a Ruby-backed callback is left to a later task.
      def run_start(ctx, settings)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_run_start_fn.call(ctx, settings, nil, nil, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # Returns the next test case, or nil once the run has finished (the
      # header documents *out_test_case as NULL at that point, with a
      # HEGEL_OK result rather than an error).
      def next_test_case(ctx, run)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_next_test_case_fn.call(ctx, run, out)
        LibHegel.check!(self, ctx, code)
        ptr = out.read_pointer
        ptr.null? ? nil : ptr
      end

      # No-op when +run+ is nil, matching hegel_run_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def run_free(ctx, run)
        @hegel_run_free_fn.call(ctx, run)
        nil
      end

      # No-op when +tc+ is nil, matching hegel_test_case_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def test_case_free(ctx, tc)
        @hegel_test_case_free_fn.call(ctx, tc)
        nil
      end

      # +origin+ must be non-nil only when +status+ is
      # HEGEL_STATUS_INTERESTING, per the header; this layer neither builds
      # nor validates that string, only passes through what the caller
      # supplies. nil marshals to NULL for this :string argument.
      def mark_complete(ctx, tc, status, origin)
        code = @hegel_mark_complete_fn.call(ctx, tc, status, origin)
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
        code = @hegel_target_fn.call(ctx, tc, value, label)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Returns a caller-owned copy of the finished run's result, or raises
      # HEGEL_E_NOT_COMPLETE (via LibHegel.check!) if the run has not
      # finished. The header documents this copy as staying valid after
      # #run_free, so +run+ can be freed as soon as this call returns; it
      # must be released separately, exactly once, with #run_result_free.
      def run_result(ctx, run)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_run_result_fn.call(ctx, run, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # No-op when +r+ is nil, matching hegel_run_result_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def run_result_free(ctx, r)
        @hegel_run_result_free_fn.call(ctx, r)
        nil
      end

      # Returns the raw hegel_run_status_t value (HEGEL_RUN_STATUS_PASSED /
      # _FAILED / _ERROR); this layer does not interpret it, matching how
      # #mark_complete passes hegel_status_t values through unexamined.
      def run_result_status(ctx, r)
        out = FFI::MemoryPointer.new(:int32)
        code = @hegel_run_result_status_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        out.read_int32
      end

      # Returns nil when the run completed normally (PASSED or FAILED),
      # matching the header's documented NULL-on-success contract for this
      # out-parameter, distinct from an empty-string message. See
      # #nullable_out_string for the ownership note shared with
      # #failure_reproduction_blob.
      def run_result_error(ctx, r)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_run_result_error_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        nullable_out_string(out)
      end

      def run_result_failure_count(ctx, r)
        out = FFI::MemoryPointer.new(:size_t)
        code = @hegel_run_result_failure_count_fn.call(ctx, r, out)
        LibHegel.check!(self, ctx, code)
        out.read_uint64
      end

      # +index+ must be less than #run_result_failure_count's value, per the
      # header. Returns a caller-owned failure handle, released separately
      # with #failure_free. Measured against libhegel 0.32.5: an
      # out-of-range +index+ comes back HEGEL_E_INVALID_ARG, even though
      # the header's Returns line for this call names only HEGEL_OK.
      def run_result_failure(ctx, r, index)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_run_result_failure_fn.call(ctx, r, index, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # No-op when +f+ is nil, matching hegel_failure_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def failure_free(ctx, f)
        @hegel_failure_free_fn.call(ctx, f)
        nil
      end

      # Copies the origin string out of libhegel's own buffer before
      # returning, since it is owned by the failure and only valid until
      # #failure_free.
      def failure_origin(ctx, f)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_failure_origin_fn.call(ctx, f, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer.read_string
      end

      # Returns nil when libhegel produced no reproduction blob for this
      # failure, matching the header's documented NULL-on-that-case
      # contract. See #nullable_out_string for the shared ownership note.
      def failure_reproduction_blob(ctx, f)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_failure_reproduction_blob_fn.call(ctx, f, out)
        LibHegel.check!(self, ctx, code)
        nullable_out_string(out)
      end

      # Replays +blob+ (from #failure_reproduction_blob) against +settings+
      # with no run handle and no run loop involved, per the header.
      # callback and user_data are always NULL here, for the same reason as
      # #run_start. +blob+ is declared :string, the same as
      # #settings_set_database's own const char* argument. Raises
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
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_test_case_from_blob_fn.call(ctx, settings, blob, nil, nil, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
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
        out = FFI::MemoryPointer.new(:bool)
        code = @hegel_generate_boolean_fn.call(ctx, tc, p, forced, has_forced, out)
        LibHegel.check!(self, ctx, code)
        out.read_uint8 != 0
      end

      def generate_integer(ctx, tc, min_value, max_value)
        out = FFI::MemoryPointer.new(:int64)
        code = @hegel_generate_integer_fn.call(ctx, tc, min_value, max_value, out)
        LibHegel.check!(self, ctx, code)
        out.read_int64
      end

      # hegel_generate_integer_big, for bounds that do not fit int64_t (see
      # Hegel::Generators::IntegerGenerator#do_draw, which dispatches here
      # instead of #generate_integer only when a bound is outside that
      # range). +min_value+/+max_value+ are encoded and the result decoded
      # via LibHegel.encode_integer_le/.decode_integer_le, which own the
      # two's-complement little-endian convention itself; this method only
      # owns the buffer marshalling around it. min_value_ptr/max_value_ptr
      # are declared :pointer, not :string: the encoded bytes routinely
      # contain interior zero bytes (256 encodes as "\x00\x01"), which a
      # NUL-terminated const char* argument would truncate. out_value's
      # capacity is the larger of the two encoded bounds, per the header's
      # "out_value_cap >= max(min_value_len, max_value_len) always
      # succeeds"; the result is read back at its own reported
      # out_value_len, not the buffer's full capacity, since
      # decode_integer_le needs only that many bytes.
      def generate_integer_big(ctx, tc, min_value, max_value)
        min_bytes = LibHegel.encode_integer_le(min_value)
        max_bytes = LibHegel.encode_integer_le(max_value)
        min_value_ptr = bytes_to_pointer(min_bytes)
        max_value_ptr = bytes_to_pointer(max_bytes)

        cap = [min_bytes.bytesize, max_bytes.bytesize].max
        out_value = FFI::MemoryPointer.new(cap)
        out_value_len = FFI::MemoryPointer.new(:size_t)

        code = @hegel_generate_integer_big_fn.call(
          ctx, tc, min_value_ptr, min_bytes.bytesize, max_value_ptr, max_bytes.bytesize, out_value, cap,
          out_value_len
        )
        LibHegel.check!(self, ctx, code)
        len = out_value_len.read_uint64
        LibHegel.decode_integer_le(out_value.read_bytes(len))
      end

      # Opens a span labelled +label+ (one of the HEGEL_LABEL_* constants,
      # or a caller-defined value that avoids them). Must be paired with
      # exactly one #stop_span call, per the header.
      def start_span(ctx, tc, label)
        code = @hegel_start_span_fn.call(ctx, tc, label)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Closes the most recently opened span. +discard+ true marks it
      # rejected, so libhegel retries from before the span opened.
      def stop_span(ctx, tc, discard)
        code = @hegel_stop_span_fn.call(ctx, tc, discard)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # Returns a caller-owned collection handle, released separately
      # with #collection_free. Pass HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
      # as +max_size+ for no upper bound, per the header.
      def new_collection(ctx, tc, min_size, max_size)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_new_collection_fn.call(ctx, tc, min_size, max_size, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # Returns whether libhegel wants another element; call in a loop,
      # drawing the next element each time this is true, until it is
      # false.
      def collection_more(ctx, tc, collection)
        out = FFI::MemoryPointer.new(:bool)
        code = @hegel_collection_more_fn.call(ctx, tc, collection, out)
        LibHegel.check!(self, ctx, code)
        out.read_uint8 != 0
      end

      # Tells libhegel the last element +collection+ produced is invalid.
      # +why+ is an optional human-readable reason (nil marshals to NULL
      # for this :string argument, which the header allows); the header
      # documents it as validated but reserved for future rejection
      # diagnostics, unused today.
      def collection_reject(ctx, tc, collection, why = nil)
        code = @hegel_collection_reject_fn.call(ctx, tc, collection, why)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # No-op when +collection+ is nil, matching hegel_collection_free's
      # documented no-op-on-NULL contract; not translated, for the same
      # reason as #context_free. Unlike every other *_free above, this
      # call takes no test-case handle: the header documents a collection
      # as independent of the test case and run it was created under.
      def collection_free(ctx, collection)
        @hegel_collection_free_fn.call(ctx, collection)
        nil
      end

      # Returns a caller-owned pool handle, released separately with
      # #pool_free. A pool tracks a set of variable ids libhegel can draw
      # from and shrink over -- mostly used for stateful testing, where a
      # rule acts on a value a previous rule generated; the caller keeps
      # its own mapping from variable id to that value, per the header.
      def new_pool(ctx, tc)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_new_pool_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # Returns a fresh variable id for the caller to associate with the
      # value it just generated. The header documents the id as drawn
      # from +tc+'s stream and recorded by value, not by pool position, so
      # it stays stable across shrinking: deleting an earlier addition
      # never renumbers the survivors.
      def pool_add(ctx, tc, pool)
        out = FFI::MemoryPointer.new(:int64)
        code = @hegel_pool_add_fn.call(ctx, tc, pool, out)
        LibHegel.check!(self, ctx, code)
        out.read_int64
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
        out = FFI::MemoryPointer.new(:int64)
        code = @hegel_pool_generate_fn.call(ctx, tc, pool, consume, out)
        LibHegel.check!(self, ctx, code)
        out.read_int64
      end

      # No-op when +pool+ is nil, matching hegel_pool_free's documented
      # no-op-on-NULL contract; not translated, for the same reason as
      # #context_free.
      def pool_free(ctx, pool)
        @hegel_pool_free_fn.call(ctx, pool)
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
        out = FFI::MemoryPointer.new(:pointer)
        # _rule_pointers / _invariant_pointers are unread past the call
        # below, the same shape #generate_integer_big's own
        # min_value_ptr/max_value_ptr already have; keeping them as local
        # variables here, not discarded inside #pack_name_array, is what
        # keeps the native buffers each one owns live through the call.
        # The leading underscore tells the linter that on purpose, the
        # same way it would for a block argument the block never reads.
        rule_names_ptr, _rule_pointers = pack_name_array(rule_names)
        invariant_names_ptr, _invariant_pointers = pack_name_array(invariant_names)

        code = @hegel_new_state_machine_fn.call(
          ctx, tc, rule_names_ptr, rule_names.size, invariant_names_ptr, invariant_names.size, out
        )
        LibHegel.check!(self, ctx, code)
        out.read_pointer
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
        out = FFI::MemoryPointer.new(:int64)
        code = @hegel_state_machine_next_rule_fn.call(ctx, tc, state_machine, out)
        LibHegel.check!(self, ctx, code)
        out.read_int64
      end

      # Reports the rule most recently returned by #state_machine_next_rule
      # as rejected (an assumption failed before it completed), so it does
      # not count toward the step budget. Raises HEGEL_E_INVALID_ARG (via
      # LibHegel.check!, translated to Hegel::Error) when no rule is
      # outstanding, per the header.
      def state_machine_rule_rejected(ctx, tc, state_machine)
        code = @hegel_state_machine_rule_rejected_fn.call(ctx, tc, state_machine)
        LibHegel.check!(self, ctx, code)
        nil
      end

      # No-op when +state_machine+ is nil, matching
      # hegel_state_machine_free's documented no-op-on-NULL contract; not
      # translated, for the same reason as #context_free.
      def state_machine_free(ctx, state_machine)
        @hegel_state_machine_free_fn.call(ctx, state_machine)
        nil
      end

      # Returns a drawn double. +smallest_nonzero_magnitude+ must be
      # positive and finite; pass
      # HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED for width
      # 64 with no restriction, per the header.
      def generate_float(ctx, tc, width, min_value, max_value, allow_nan, allow_infinity, exclude_min, exclude_max,
        smallest_nonzero_magnitude)
        out = FFI::MemoryPointer.new(:double)
        code = @hegel_generate_float_fn.call(ctx, tc, width, min_value, max_value, allow_nan, allow_infinity,
          exclude_min, exclude_max, smallest_nonzero_magnitude, out)
        LibHegel.check!(self, ctx, code)
        out.read_double
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
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_string_generator_text_fn.call(
          ctx, min_size, max_size, codec, min_codepoint, max_codepoint,
          nil, 0, nil, 0, nil, 0, nil, 0,
          out
        )
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # No-op when +generator+ is nil, matching
      # hegel_string_generator_free's documented no-op-on-NULL contract;
      # not translated, for the same reason as #context_free.
      def string_generator_free(ctx, generator)
        @hegel_string_generator_free_fn.call(ctx, generator)
        nil
      end

      # Returns a drawn String, force-encoded as UTF-8 (this codec's
      # alphabet), copying exactly the returned +len+ bytes rather than
      # reading a NUL-terminated buffer: the header documents it as not
      # NUL-terminated and possibly containing interior NUL bytes, since
      # the drawn alphabet can include U+0000.
      #
      # The native buffer is released in +ensure+ via
      # #generate_string_result_free, called directly from here rather
      # than left to the caller: nothing outside this file may hold or
      # read the raw struct (ffi is confined to this file), so unlike
      # #new_collection or #string_generator_text, the freeable handle
      # here never leaves this method. Freeing is safe even when the draw
      # above raised: +out+ starts zero-filled (FFI::Struct.new allocates
      # cleared memory) and libhegel only writes into it on success, so
      # the struct #generate_string_result_free sees here is always
      # either a completed draw or the all-zero state the header
      # documents as already safe to free.
      def generate_string(ctx, tc, generator)
        out = RawResultStruct.new
        code = @hegel_generate_string_fn.call(ctx, tc, generator, out)
        LibHegel.check!(self, ctx, code)
        out[:data].read_bytes(out[:len]).force_encoding(Encoding::UTF_8)
      ensure
        generate_string_result_free(ctx, out)
      end

      # No-op when +result+ is nil, matching
      # hegel_generate_string_result_free's documented no-op-on-NULL
      # contract (also safe on an already-freed, zeroed struct); not
      # translated, for the same reason as #context_free.
      def generate_string_result_free(ctx, result)
        @hegel_generate_string_result_free_fn.call(ctx, result)
        nil
      end

      # Returns drawn bytes as a String, read via +len+ the same way
      # #generate_string reads its own out-parameter: the header gives no
      # NUL-termination guarantee for this buffer either, so the length is
      # what makes the copy exact.
      #
      # Unlike #generate_string, the result is never force-encoded.
      # hegel_generate_bytes_result_t is documented as a byte buffer, not
      # text, and FFI::Pointer#read_bytes already returns ASCII-8BIT
      # (Encoding::BINARY), which is the encoding a byte string belongs in.
      #
      # The native buffer is released in +ensure+ via
      # #generate_bytes_result_free, for the same reason #generate_string
      # frees its own result from inside this file: ffi is confined to
      # this file, so the freeable handle never leaves this method. Freeing
      # is safe even when the draw above raised, for the same
      # zero-filled-allocation reason documented on #generate_string: the
      # header documents hegel_generate_bytes_result_free as safe on an
      # already-freed (zeroed) struct too.
      def generate_bytes(ctx, tc, min_size, max_size)
        out = RawResultStruct.new
        code = @hegel_generate_bytes_fn.call(ctx, tc, min_size, max_size, out)
        LibHegel.check!(self, ctx, code)
        out[:data].read_bytes(out[:len])
      ensure
        generate_bytes_result_free(ctx, out)
      end

      # No-op when +result+ is nil, matching
      # hegel_generate_bytes_result_free's documented no-op-on-NULL
      # contract (also safe on an already-freed, zeroed struct); not
      # translated, for the same reason as #context_free.
      def generate_bytes_result_free(ctx, result)
        @hegel_generate_bytes_result_free_fn.call(ctx, result)
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
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_string_generator_regex_fn.call(ctx, pattern, fullmatch, alphabet, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # Returns a caller-owned string generator handle producing RFC
      # 5321/5322 email addresses, released the same way as
      # #string_generator_text.
      def string_generator_email(ctx)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_string_generator_email_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # Returns a caller-owned string generator handle producing RFC 3986
      # http/https URLs, released the same way as #string_generator_text.
      def string_generator_url(ctx)
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_string_generator_url_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
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
        out = FFI::MemoryPointer.new(:pointer)
        code = @hegel_string_generator_domain_fn.call(ctx, max_length, out)
        LibHegel.check!(self, ctx, code)
        out.read_pointer
      end

      # hegel_generate_ipv4 writes into a caller-supplied fixed-length
      # buffer instead of handing back a pointer through an out-parameter,
      # unlike every generate_* call above: the header documents out_bytes
      # as the address's 4 network-order bytes with no separate length to
      # read, so the buffer's own size is the contract instead of a
      # trailing len field. IPAddr conversion is left to the generator
      # built on top of this call; this layer returns the raw bytes.
      def generate_ipv4(ctx, tc)
        out = FFI::MemoryPointer.new(4)
        code = @hegel_generate_ipv4_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.read_bytes(4)
      end

      # Same fixed-buffer shape as #generate_ipv4, sized for the header's
      # documented 16 network-order bytes.
      def generate_ipv6(ctx, tc)
        out = FFI::MemoryPointer.new(16)
        code = @hegel_generate_ipv6_fn.call(ctx, tc, out)
        LibHegel.check!(self, ctx, code)
        out.read_bytes(16)
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
        out = FFI::MemoryPointer.new(16)
        code = @hegel_generate_uuid_fn.call(ctx, tc, version, has_version, out)
        LibHegel.check!(self, ctx, code)
        out.read_bytes(16)
      end

      # hegel_generate_date. +min_value+/+max_value+ are each a
      # [year, month, day] Array, written by #date_struct into a
      # DateStruct passed .by_value (see the comment on that class, above
      # #initialize). Returns a [year, month, day] Array, the field-level
      # shape Hegel::Generators::DatesGenerator builds its own Date from --
      # the same division of labor #generate_ipv4/#generate_uuid already
      # follow, returning raw values for a generator one layer up to turn
      # into the caller-facing type. This layer does not validate
      # year/month/day itself: measured against libhegel 0.32.5, an
      # invalid date (month 13, say) already comes back
      # HEGEL_E_INVALID_ARG, translated by LibHegel.check! below, even
      # though the header's Returns line for this call names only
      # HEGEL_OK/HEGEL_E_STOP_TEST -- the same gap #run_result_failure's own
      # comment already notes for a different call.
      def generate_date(ctx, tc, min_value, max_value)
        out = DateStruct.new
        code = @hegel_generate_date_fn.call(ctx, tc, date_struct(min_value), date_struct(max_value), out)
        LibHegel.check!(self, ctx, code)
        read_date(out)
      end

      # hegel_generate_time. +min_value+/+max_value+ are each an
      # [hour, minute, second, microsecond] Array; same struct-passing,
      # return shape, and validation division of labor as #generate_date
      # above, for Hegel::Generators::TimesGenerator.
      def generate_time(ctx, tc, min_value, max_value)
        out = TimeStruct.new
        code = @hegel_generate_time_fn.call(ctx, tc, time_struct(min_value), time_struct(max_value), out)
        LibHegel.check!(self, ctx, code)
        read_time(out)
      end

      # hegel_generate_datetime. +min_date+/+max_date+ are each a
      # [year, month, day] Array; +min_time+/+max_time+ are each an
      # [hour, minute, second, microsecond] Array -- hegel_datetime_t is a
      # hegel_date_t followed by a hegel_time_t (see DatetimeStruct's own
      # layout, above #initialize). Returns a
      # [[year, month, day], [hour, minute, second, microsecond]] pair, for
      # Hegel::Generators::DatetimesGenerator to build its own Time from.
      def generate_datetime(ctx, tc, min_date, min_time, max_date, max_time)
        out = DatetimeStruct.new
        code = @hegel_generate_datetime_fn.call(
          ctx, tc, datetime_struct(min_date, min_time), datetime_struct(max_date, max_time), out
        )
        LibHegel.check!(self, ctx, code)
        [read_date(out[:date]), read_time(out[:time])]
      end

      private

      # Resolves +symbol+ against @handle and wraps it as a callable
      # FFI::Function, the direct form #initialize's own comment explains
      # the choice of.
      def bind(symbol, arg_types, ret_type)
        FFI::Function.new(ret_type, arg_types, @handle.find_function(symbol))
      end

      # Copies +bytes+ into a freshly allocated buffer, for
      # #generate_integer_big's min_value/max_value: a const uint8_t*
      # argument libhegel reads from, the opposite direction of an
      # out-parameter buffer (which libhegel writes into, and the caller
      # then reads).
      def bytes_to_pointer(bytes)
        ptr = FFI::MemoryPointer.new(bytes.bytesize)
        ptr.put_bytes(0, bytes)
        ptr
      end

      # Packs +names+ (an Array of Ruby Strings) into a const char *const *
      # for #new_state_machine's rule_names/invariant_names arguments: one
      # address per name, written into a single buffer via
      # write_array_of_pointer.
      #
      # Returns [pointer, kept_alive]. FFI::MemoryPointer.from_string
      # copies each name into a fresh native buffer that Ruby object owns
      # -- unlike a pointer built straight off a Ruby String's own bytes,
      # nothing here depends on the original +names+ Strings staying live
      # -- so what must stay live until the native call reads them is the
      # per-name FFI::MemoryPointer array itself; write_array_of_pointer
      # only copies the addresses those objects report, not a reference to
      # the objects, so the caller keeping +kept_alive+ as a live local for
      # the length of the call is what keeps the buffers each one owns
      # from being garbage-collected first.
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

        pointers = names.map { |name| FFI::MemoryPointer.from_string(name) }
        array = FFI::MemoryPointer.new(:pointer, names.size)
        array.write_array_of_pointer(pointers)
        [array, pointers]
      end

      # Writes +value+ (a [year, month, day] Array) into +struct+'s own
      # :year/:month/:day fields. Shared by #date_struct, which builds a
      # standalone DateStruct, and #datetime_struct, which writes the same
      # three fields into a DatetimeStruct's embedded :date view instead
      # -- both are plain FFI::Struct field assignment, so the same method
      # writes either one.
      def write_date(struct, value)
        year, month, day = value
        struct[:year] = year
        struct[:month] = month
        struct[:day] = day
      end

      # The #write_date/#date_struct counterpart for a [hour, minute,
      # second, microsecond] Array.
      def write_time(struct, value)
        hour, minute, second, microsecond = value
        struct[:hour] = hour
        struct[:minute] = minute
        struct[:second] = second
        struct[:microsecond] = microsecond
      end

      # A standalone DateStruct built from +value+, for #generate_date's
      # min_value/max_value arguments.
      def date_struct(value)
        struct = DateStruct.new
        write_date(struct, value)
        struct
      end

      # The #date_struct counterpart for #generate_time's own arguments.
      def time_struct(value)
        struct = TimeStruct.new
        write_time(struct, value)
        struct
      end

      # A DatetimeStruct built from +date+ and +time+, for
      # #generate_datetime's min/max arguments. Writes directly into the
      # struct's embedded :date/:time fields rather than building two
      # standalone structs and copying, since an embedded field is already
      # a view onto the same memory (see #write_date/#write_time).
      def datetime_struct(date, time)
        struct = DatetimeStruct.new
        write_date(struct[:date], date)
        write_time(struct[:time], time)
        struct
      end

      # Reads +struct+'s :year/:month/:day fields back into a
      # [year, month, day] Array, the inverse of #write_date. Shared by
      # #generate_date (a standalone DateStruct out-parameter) and
      # #generate_datetime (the embedded :date view of a DatetimeStruct
      # out-parameter).
      def read_date(struct)
        [struct[:year], struct[:month], struct[:day]]
      end

      # The #read_date counterpart for a struct's :hour/:minute/:second/
      # :microsecond fields.
      def read_time(struct)
        [struct[:hour], struct[:minute], struct[:second], struct[:microsecond]]
      end

      # Reads +out+'s const char* out-parameter into a Ruby String, or
      # returns nil if libhegel left it NULL. Shared by #run_result_error
      # and #failure_reproduction_blob, the two out-parameters the header
      # documents as nullable, so both branches only need to be exercised
      # once between the two call sites rather than at each one.
      def nullable_out_string(out)
        ptr = out.read_pointer
        ptr.null? ? nil : ptr.read_string
      end
    end
  end
end
