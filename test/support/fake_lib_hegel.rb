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
    # wants to exercise. The most useful case is an error code that drives
    # LibHegel.check! down a path the real engine would rarely take.
    class Fake
      # The handle #run_result_failure hands back. Bundles the origin, blob,
      # and caveat a test configured at that index via #failure_origins= /
      # #failure_blobs= / #failure_caveats=, so #failure_origin /
      # #failure_reproduction_blob / #failure_caveat can read them straight
      # off the handle, mirroring how the real ABI's opaque failure handle
      # already carries that state.
      Failure = Struct.new(:origin, :blob, :caveat)

      RECURSION_MAX_ATTEMPTS = 9

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
      attr_writer :settings_new_code, :settings_new_for_profile_code, :settings_register_profile_code,
        :set_default_profile_code, :settings_set_test_cases_code, :settings_set_verbosity_code,
        :settings_set_seed_code, :settings_set_derandomize_code, :settings_set_database_code,
        :run_start_code, :next_test_case_code, :mark_complete_code,
        :generate_boolean_code, :generate_integer_code, :generate_integer_big_code,
        :run_result_code, :run_result_status_code, :run_result_error_code,
        :run_result_failure_count_code, :run_result_failure_code,
        :failure_origin_code, :failure_reproduction_blob_code, :failure_caveat_code,
        :run_start_blob_code, :test_case_should_capture_code,
        :start_span_code, :stop_span_code,
        :new_collection_code, :collection_more_code, :collection_reject_code,
        :generate_float_code, :string_generator_text_code, :generate_string_code,
        :generate_bytes_code, :string_generator_regex_code, :string_generator_email_code,
        :string_generator_url_code, :string_generator_domain_code, :generate_ipv4_code, :generate_ipv6_code,
        :generate_uuid_code, :generate_date_code, :generate_time_code, :generate_datetime_code,
        :settings_set_phases_code, :settings_set_suppress_health_check_code,
        :settings_set_report_multiple_failures_code, :settings_set_database_key_code, :settings_set_test_location_code,
        :target_code,
        :new_pool_code, :pool_add_code, :pool_generate_code, :pool_restore_code,
        :new_state_machine_code, :state_machine_next_group_code, :state_machine_next_rule_code,
        :state_machine_rule_rejected_code, :state_machine_should_check_invariant_code,
        :grammar_builder_new_code, :grammar_builder_file_code, :grammar_builder_provide_code, :grammar_new_code,
        :grammar_placeholder_code, :generate_grammar_code

      # The paths #grammar_builder_file answers, by index, and the strings
      # #generate_grammar answers, one per call in order, then "".
      attr_writer :grammar_builder_files, :generate_grammar_values

      # What the grammar calls were given: each builder's text, each
      # [builder, index, text] provided, a Hash of each #grammar_new call's
      # arguments, and the max_size of each #generate_grammar call.
      attr_reader :grammar_builder_texts, :grammar_builder_provides, :grammar_new_calls, :generate_grammar_max_sizes,
        :freed_grammar_builders, :freed_grammars

      # context_free, the grammar calls, and spans, in the order they were
      # made, so a test can check one happened before another.
      attr_reader :events

      # Values #pool_add / #pool_generate / #state_machine_next_group /
      # #state_machine_next_rule / #state_machine_should_check_invariant hand
      # back on success.
      attr_writer :pool_add_value, :pool_generate_value, :state_machine_next_group_value,
        :state_machine_next_rule_value, :state_machine_should_check_invariant_value

      # Values #generate_boolean / #generate_integer / #generate_integer_big
      # hand back on success.
      attr_writer :generate_boolean_value, :generate_integer_value, :generate_integer_big_value

      # Value #generate_float hands back on success.
      attr_writer :generate_float_value

      # Value #generate_string hands back on success.
      attr_writer :generate_string_value

      # Values #generate_bytes / #generate_ipv4 / #generate_ipv6 / #generate_uuid hand back
      # on success.
      attr_writer :generate_bytes_value, :generate_ipv4_value, :generate_ipv6_value, :generate_uuid_value

      # Values #generate_date / #generate_time / #generate_datetime hand
      # back on success.
      attr_writer :generate_date_value, :generate_time_value, :generate_datetime_value

      # Number of times #collection_more answers true before it answers
      # false, mirroring #test_case_count / @cases_served below so a loop
      # driven against this Fake terminates.
      attr_writer :collection_more_count

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
      # none for that failure; a caveat of nil, a deterministic failure.
      attr_writer :failure_count, :failure_origins, :failure_blobs, :failure_caveats

      # What #test_case_should_capture answers: one boolean for every case, or
      # an Array answered one element per case in order. True by default,
      # so every failing case records its draws, as the engine's stamped
      # final replay would.
      attr_writer :should_capture

      # Every blob #run_start_blob was given, in call order.
      attr_reader :run_start_blobs

      # Whether #run_start's out-parameter comes back NULL despite a
      # HEGEL_OK result, distinct from an error via #run_start_code=.
      attr_writer :run_start_returns_nil

      attr_reader :freed_contexts, :freed_settings, :freed_test_cases, :marked_statuses, :marked_origins, :freed_string_generators,
        :freed_pools, :state_machine_rule_weights, :restored_pool_ids, :opened_collections, :freed_collections

      # The arguments of each #string_generator_text call (a Hash of its
      # keywords) and each #string_generator_regex call (a Hash of pattern,
      # fullmatch and alphabet), paired with the handle that call returned.
      attr_reader :string_generator_text_calls, :string_generator_regex_calls
      # Result codes and branch decisions the recursion calls answer with,
      # one element per call in order. #new_recursion_calls holds the
      # [max_depth, max_leaves] pair each #new_recursion call was given.
      attr_writer :new_recursion_code, :recursion_branch_code, :recursion_branch_values, :recursion_leaf_codes,
        :recursion_retry_codes, :recursion_finish_codes
      attr_reader :new_recursion_calls, :freed_recursions

      # The value passed to each settings setter, one array per keyword, so
      # a test can confirm Hegel::Settings.apply calls the setter its table
      # names with the value it was given (and that a nil keyword calls no
      # setter at all). #settings_seed_calls holds [seed, has_seed] pairs,
      # matching hegel_settings_set_seed's two value arguments.
      attr_reader :settings_test_cases_calls, :settings_verbosity_calls, :settings_seed_calls,
        :settings_derandomize_calls, :settings_database_calls, :settings_database_key_calls,
        :settings_phases_calls, :settings_suppress_health_check_calls, :settings_report_multiple_failures_calls,
        :settings_stop_on_first_failure_calls, :settings_print_blob_calls, :settings_show_statistics_calls,
        :settings_nondeterminism_strictness_calls, :settings_backend_calls, :settings_test_location_calls, :event_calls, :event_value_calls,
        :settings_new_for_profile_calls, :settings_register_profile_calls, :set_default_profile_calls

      # What #settings_get_print_blob reports: true, the engine's own default,
      # unless a test sets it to stand in for a profile that turns it off.
      attr_accessor :settings_print_blob_value

      def initialize
        @version = Hegel::LIBHEGEL_VERSION
        @version_code = HEGEL_OK
        @last_error = "fake error"
        @freed_contexts = []
        @freed_settings = []
        @freed_test_cases = []
        @freed_string_generators = []
        @string_generator_text_calls = []
        @string_generator_regex_calls = []
        @freed_pools = []
        @state_machine_rule_weights = []
        @restored_pool_ids = []
        @opened_collections = []
        @freed_collections = []

        @settings_new_code = HEGEL_OK
        @settings_new_for_profile_code = HEGEL_OK
        @settings_register_profile_code = HEGEL_OK
        @set_default_profile_code = HEGEL_OK
        @settings_new_for_profile_calls = []
        @settings_register_profile_calls = []
        @set_default_profile_calls = []
        @settings_set_test_cases_code = HEGEL_OK
        @settings_set_verbosity_code = HEGEL_OK
        @settings_set_seed_code = HEGEL_OK
        @settings_set_derandomize_code = HEGEL_OK
        @settings_set_database_code = HEGEL_OK
        @settings_test_cases_calls = []
        @settings_verbosity_calls = []
        @settings_seed_calls = []
        @settings_derandomize_calls = []
        @settings_database_calls = []
        @settings_database_key_calls = []
        @settings_test_location_calls = []
        @settings_phases_calls = []
        @settings_suppress_health_check_calls = []
        @settings_report_multiple_failures_calls = []
        @settings_stop_on_first_failure_calls = []
        @settings_print_blob_calls = []
        @settings_show_statistics_calls = []
        @settings_nondeterminism_strictness_calls = []
        @settings_backend_calls = []
        @settings_print_blob_value = true
        @event_calls = []
        @event_value_calls = []

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
        @generate_integer_big_code = HEGEL_OK
        @generate_integer_big_value = 0

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
        @failure_caveats = []
        @failure_origin_code = HEGEL_OK
        @failure_reproduction_blob_code = HEGEL_OK
        @failure_caveat_code = HEGEL_OK
        @run_start_blob_code = HEGEL_OK
        @run_start_blobs = []
        @test_case_should_capture_code = HEGEL_OK
        @should_capture = true

        @start_span_code = HEGEL_OK
        @stop_span_code = HEGEL_OK

        @new_collection_code = HEGEL_OK
        @collection_more_code = HEGEL_OK
        @collection_more_count = 0
        @collection_more_served = 0
        @collection_reject_code = HEGEL_OK

        @generate_float_code = HEGEL_OK
        @generate_float_value = 0.0

        @string_generator_text_code = HEGEL_OK
        @generate_string_code = HEGEL_OK
        @generate_string_value = ""

        @generate_bytes_code = HEGEL_OK
        @generate_bytes_value = "".b
        @string_generator_regex_code = HEGEL_OK
        @string_generator_email_code = HEGEL_OK
        @string_generator_url_code = HEGEL_OK
        @string_generator_domain_code = HEGEL_OK
        @generate_ipv4_code = HEGEL_OK
        @generate_ipv4_value = "\x00\x00\x00\x00".b
        @generate_ipv6_code = HEGEL_OK
        @generate_ipv6_value = ("\x00" * 16).b
        @generate_uuid_code = HEGEL_OK
        @generate_uuid_value = ("\x00" * 16).b

        @generate_date_code = HEGEL_OK
        @generate_date_value = [1, 1, 1]
        @generate_time_code = HEGEL_OK
        @generate_time_value = [0, 0, 0, 0]
        @generate_datetime_code = HEGEL_OK
        @generate_datetime_value = [[1, 1, 1], [0, 0, 0, 0]]

        @settings_set_phases_code = HEGEL_OK
        @settings_set_suppress_health_check_code = HEGEL_OK
        @settings_set_report_multiple_failures_code = HEGEL_OK
        @settings_set_database_key_code = HEGEL_OK
        @settings_set_test_location_code = HEGEL_OK

        @target_code = HEGEL_OK

        @new_pool_code = HEGEL_OK
        @pool_add_code = HEGEL_OK
        @pool_add_value = 0
        @pool_generate_code = HEGEL_OK
        @pool_generate_value = 0
        @pool_restore_code = HEGEL_OK
        @new_state_machine_code = HEGEL_OK
        # The machine ends before its first round unless a test says
        # otherwise, so a test that opens one never loops by accident.
        @state_machine_next_group_code = HEGEL_OK
        @state_machine_next_group_value = HEGEL_STATE_MACHINE_DONE
        @state_machine_next_rule_code = HEGEL_OK
        @state_machine_next_rule_value = 0
        @state_machine_rule_rejected_code = HEGEL_OK
        @state_machine_should_check_invariant_code = HEGEL_OK
        @state_machine_should_check_invariant_value = true

        @grammar_builder_new_code = HEGEL_OK
        @grammar_builder_file_code = HEGEL_OK
        @grammar_builder_provide_code = HEGEL_OK
        @grammar_new_code = HEGEL_OK
        @grammar_placeholder_code = HEGEL_OK
        @generate_grammar_code = HEGEL_OK
        @grammar_builder_files = []
        @generate_grammar_values = []
        @grammar_builder_texts = []
        @grammar_builder_provides = []
        @grammar_new_calls = []
        @generate_grammar_max_sizes = []
        @freed_grammar_builders = []
        @freed_grammars = []
        @events = []
        @new_recursion_code = HEGEL_OK
        @new_recursion_calls = []
        @recursion_branch_code = HEGEL_OK
        @recursion_branch_values = []
        @recursion_leaf_codes = []
        @recursion_retry_codes = []
        @recursion_retries = Hash.new(0).compare_by_identity
        @recursion_finish_codes = []
        @freed_recursions = []
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
        @events << [:context_free]
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

      def settings_new_for_profile(ctx, name)
        @settings_new_for_profile_calls << name
        LibHegel.check!(self, ctx, @settings_new_for_profile_code)
        Object.new
      end

      def settings_register_profile(ctx, name, s)
        @settings_register_profile_calls << [name, s]
        LibHegel.check!(self, ctx, @settings_register_profile_code)
        nil
      end

      def set_default_profile(ctx, name)
        @set_default_profile_calls << name
        LibHegel.check!(self, ctx, @set_default_profile_code)
        nil
      end

      def settings_free(_ctx, s)
        @freed_settings << s
        nil
      end

      def settings_set_test_cases(ctx, _s, n)
        @settings_test_cases_calls << n
        LibHegel.check!(self, ctx, @settings_set_test_cases_code)
        nil
      end

      def settings_set_verbosity(ctx, _s, v)
        @settings_verbosity_calls << v
        LibHegel.check!(self, ctx, @settings_set_verbosity_code)
        nil
      end

      def settings_set_seed(ctx, _s, seed, has_seed)
        @settings_seed_calls << [seed, has_seed]
        LibHegel.check!(self, ctx, @settings_set_seed_code)
        nil
      end

      def settings_set_derandomize(ctx, _s, derandomize)
        @settings_derandomize_calls << derandomize
        LibHegel.check!(self, ctx, @settings_set_derandomize_code)
        nil
      end

      def settings_set_database(ctx, _s, database)
        @settings_database_calls << database
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

      # Records +blob+ (readable via #run_start_blobs), then answers like
      # #run_start: the cases it serves are the replay's.
      def run_start_blob(ctx, _settings, blob)
        @run_start_blobs << blob
        LibHegel.check!(self, ctx, @run_start_blob_code)
        Object.new
      end

      def test_case_should_capture(ctx, _tc)
        LibHegel.check!(self, ctx, @test_case_should_capture_code)
        @should_capture.is_a?(Array) ? @should_capture.shift : @should_capture
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

      # Records +tc+ (readable via #freed_test_cases), so a test can confirm
      # the caller freed a handle even along a path (a fatal exception) that
      # skips #mark_complete.
      def test_case_free(_ctx, tc)
        @freed_test_cases << tc
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

      def generate_integer_big(ctx, _tc, _min_value, _max_value)
        LibHegel.check!(self, ctx, @generate_integer_big_code)
        @generate_integer_big_value
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

      # Returns a Failure bundling the origin / blob / caveat configured at
      # +index+ via #failure_origins= / #failure_blobs= / #failure_caveats=.
      # An origin left unconfigured is the index-th distinct origin a case
      # was marked INTERESTING with, as the real engine groups a failure
      # under the origin the caller reported.
      def run_result_failure(ctx, _r, index)
        LibHegel.check!(self, ctx, @run_result_failure_code)
        origin = @failure_origins[index] || interesting_origins[index]
        Failure.new(origin, @failure_blobs[index], @failure_caveats[index])
      end

      def interesting_origins
        @marked_statuses.zip(@marked_origins).filter_map { |status, origin| origin if status == HEGEL_STATUS_INTERESTING }.uniq
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

      def failure_caveat(ctx, f)
        LibHegel.check!(self, ctx, @failure_caveat_code)
        f.caveat
      end

      def start_span(ctx, _tc, label)
        @events << [:start_span, label]
        LibHegel.check!(self, ctx, @start_span_code)
        nil
      end

      def stop_span(ctx, _tc, discard)
        @events << [:stop_span, discard]
        LibHegel.check!(self, ctx, @stop_span_code)
        nil
      end

      # Records each collection it opens as [handle, min_size, max_size],
      # and #collection_free records each handle it frees, so a test can
      # pair every opened collection with its release.
      def new_collection(ctx, _tc, min_size, max_size)
        LibHegel.check!(self, ctx, @new_collection_code)
        collection = Object.new
        @opened_collections << [collection, min_size, max_size]
        collection
      end

      # Answers true @collection_more_count times, then false, matching
      # #next_test_case's count-then-nil shape so a loop against this
      # Fake terminates.
      def collection_more(ctx, _tc, _collection)
        LibHegel.check!(self, ctx, @collection_more_code)
        return false if @collection_more_served >= @collection_more_count

        @collection_more_served += 1
        true
      end

      def collection_reject(ctx, _tc, _collection, _why = nil)
        LibHegel.check!(self, ctx, @collection_reject_code)
        nil
      end

      def collection_free(_ctx, collection)
        @freed_collections << collection
        nil
      end

      def generate_float(ctx, _tc, _width, _min_value, _max_value, _allow_nan, _allow_infinity, _exclude_min,
        _exclude_max, _smallest_nonzero_magnitude)
        LibHegel.check!(self, ctx, @generate_float_code)
        @generate_float_value
      end

      def string_generator_text(ctx, min_size:, max_size:, codec: nil, min_codepoint: 0, max_codepoint: 0xFFFFFFFF,
        categories: nil, exclude_categories: nil, include_characters: "", exclude_characters: "")
        LibHegel.check!(self, ctx, @string_generator_text_code)
        options = {
          min_size: min_size, max_size: max_size, codec: codec, min_codepoint: min_codepoint,
          max_codepoint: max_codepoint, categories: categories, exclude_categories: exclude_categories,
          include_characters: include_characters, exclude_characters: exclude_characters
        }
        Object.new.tap { |handle| @string_generator_text_calls << [options, handle] }
      end

      # Records +generator+, so a test can confirm
      # Hegel::TestCase#with_text_generator freed the handle it yielded,
      # mirroring #context_free / #freed_contexts for with_context.
      def string_generator_free(_ctx, generator)
        @freed_string_generators << generator
        nil
      end

      def generate_string(ctx, _tc, _generator)
        LibHegel.check!(self, ctx, @generate_string_code)
        @generate_string_value
      end

      def owned_string_free(_ctx, _result)
        nil
      end

      def generate_bytes(ctx, _tc, _min_size, _max_size)
        LibHegel.check!(self, ctx, @generate_bytes_code)
        @generate_bytes_value
      end

      def generate_bytes_result_free(_ctx, _result)
        nil
      end

      def string_generator_regex(ctx, pattern, fullmatch, alphabet = nil)
        LibHegel.check!(self, ctx, @string_generator_regex_code)
        Object.new.tap do |handle|
          @string_generator_regex_calls << [{pattern: pattern, fullmatch: fullmatch, alphabet: alphabet}, handle]
        end
      end

      def string_generator_email(ctx)
        LibHegel.check!(self, ctx, @string_generator_email_code)
        Object.new
      end

      def string_generator_url(ctx)
        LibHegel.check!(self, ctx, @string_generator_url_code)
        Object.new
      end

      def string_generator_domain(ctx, _max_length)
        LibHegel.check!(self, ctx, @string_generator_domain_code)
        Object.new
      end

      def generate_ipv4(ctx, _tc)
        LibHegel.check!(self, ctx, @generate_ipv4_code)
        @generate_ipv4_value
      end

      def generate_ipv6(ctx, _tc)
        LibHegel.check!(self, ctx, @generate_ipv6_code)
        @generate_ipv6_value
      end

      def generate_uuid(ctx, _tc, _version, _has_version)
        LibHegel.check!(self, ctx, @generate_uuid_code)
        @generate_uuid_value
      end

      def generate_date(ctx, _tc, _min_value, _max_value)
        LibHegel.check!(self, ctx, @generate_date_code)
        @generate_date_value
      end

      def generate_time(ctx, _tc, _min_value, _max_value)
        LibHegel.check!(self, ctx, @generate_time_code)
        @generate_time_value
      end

      def generate_datetime(ctx, _tc, _min_date, _min_time, _max_date, _max_time)
        LibHegel.check!(self, ctx, @generate_datetime_code)
        @generate_datetime_value
      end

      def settings_set_phases(ctx, _s, phases)
        @settings_phases_calls << phases
        LibHegel.check!(self, ctx, @settings_set_phases_code)
        nil
      end

      def settings_set_suppress_health_check(ctx, _s, checks)
        @settings_suppress_health_check_calls << checks
        LibHegel.check!(self, ctx, @settings_set_suppress_health_check_code)
        nil
      end

      def settings_set_report_multiple_failures(ctx, _s, yes)
        @settings_report_multiple_failures_calls << yes
        LibHegel.check!(self, ctx, @settings_set_report_multiple_failures_code)
        nil
      end

      def settings_set_database_key(ctx, _s, key)
        @settings_database_key_calls << key
        LibHegel.check!(self, ctx, @settings_set_database_key_code)
        nil
      end

      def settings_set_test_location(ctx, _s, file, begin_line, class_name, function)
        @settings_test_location_calls << [file, begin_line, class_name, function]
        LibHegel.check!(self, ctx, @settings_set_test_location_code)
        nil
      end

      def settings_set_stop_on_first_failure(_ctx, _s, yes)
        @settings_stop_on_first_failure_calls << yes
        nil
      end

      # Also updates what #settings_get_print_blob reads back, as the engine
      # does.
      def settings_set_print_blob(_ctx, _s, yes)
        @settings_print_blob_calls << yes
        @settings_print_blob_value = yes
        nil
      end

      def settings_get_print_blob(_ctx, _s)
        @settings_print_blob_value
      end

      def settings_set_show_statistics(_ctx, _s, yes)
        @settings_show_statistics_calls << yes
        nil
      end

      def settings_set_nondeterminism_strictness(_ctx, _s, strictness)
        @settings_nondeterminism_strictness_calls << strictness
        nil
      end

      def settings_set_backend(_ctx, _s, backend)
        @settings_backend_calls << backend
        nil
      end

      def event(_ctx, _tc, label)
        @event_calls << label
        nil
      end

      def event_value(_ctx, _tc, label, value)
        @event_value_calls << [label, value]
        nil
      end

      def target(ctx, _tc, _value, _label)
        LibHegel.check!(self, ctx, @target_code)
        nil
      end

      def new_pool(ctx, _tc)
        LibHegel.check!(self, ctx, @new_pool_code)
        Object.new
      end

      def pool_add(ctx, _tc, _pool)
        LibHegel.check!(self, ctx, @pool_add_code)
        @pool_add_value
      end

      def pool_generate(ctx, _tc, _pool, _consume)
        LibHegel.check!(self, ctx, @pool_generate_code)
        @pool_generate_value
      end

      def pool_restore(ctx, _tc, _pool, variable_id)
        LibHegel.check!(self, ctx, @pool_restore_code)
        @restored_pool_ids << variable_id
        nil
      end

      # Records +pool+ (readable via #freed_pools), so a test can confirm
      # Hegel::Runner freed every pool a test case opened, whether the case
      # came from an ordinary run or from a reproduce_failure: replay.
      def pool_free(_ctx, pool)
        @freed_pools << pool
        nil
      end

      def new_state_machine(ctx, _tc, _rule_names, rule_weights, _invariant_names, _always_check, _step_count)
        @state_machine_rule_weights << rule_weights
        LibHegel.check!(self, ctx, @new_state_machine_code)
        Object.new
      end

      def state_machine_next_group(ctx, _tc, _state_machine)
        LibHegel.check!(self, ctx, @state_machine_next_group_code)
        @state_machine_next_group_value
      end

      def state_machine_next_rule(ctx, _tc, _state_machine)
        LibHegel.check!(self, ctx, @state_machine_next_rule_code)
        @state_machine_next_rule_value
      end

      def state_machine_rule_rejected(ctx, _tc, _state_machine)
        LibHegel.check!(self, ctx, @state_machine_rule_rejected_code)
        nil
      end

      def state_machine_should_check_invariant(ctx, _tc, _state_machine, _index)
        LibHegel.check!(self, ctx, @state_machine_should_check_invariant_code)
        @state_machine_should_check_invariant_value
      end

      def state_machine_free(_ctx, _state_machine)
        nil
      end

      def grammar_builder_new(ctx, text)
        LibHegel.check!(self, ctx, @grammar_builder_new_code)
        @grammar_builder_texts << text
        Object.new
      end

      def grammar_builder_file(ctx, _builder, index)
        LibHegel.check!(self, ctx, @grammar_builder_file_code)
        @grammar_builder_files[index]
      end

      def grammar_builder_provide(ctx, builder, index, text)
        @grammar_builder_provides << [builder, index, text]
        LibHegel.check!(self, ctx, @grammar_builder_provide_code)
        nil
      end

      def grammar_builder_free(_ctx, builder)
        @freed_grammar_builders << builder
        nil
      end

      def grammar_new(ctx, builder, start, max_size, max_depth, alphabet, names)
        @grammar_new_calls << {
          builder: builder, start: start, max_size: max_size, max_depth: max_depth, alphabet: alphabet, names: names
        }
        LibHegel.check!(self, ctx, @grammar_new_code)
        Object.new.tap { |grammar| @events << [:grammar_new, grammar] }
      end

      def grammar_placeholder(ctx, _grammar, name)
        LibHegel.check!(self, ctx, @grammar_placeholder_code)
        "<<EXPLICIT_#{name}_fake>>"
      end

      def grammar_free(_ctx, grammar)
        @freed_grammars << grammar
        @events << [:grammar_free, grammar]
        nil
      end

      def generate_grammar(ctx, _tc, _grammar, max_size)
        @generate_grammar_max_sizes << max_size
        @events << [:generate_grammar, max_size]
        LibHegel.check!(self, ctx, @generate_grammar_code)
        @generate_grammar_values.shift || ""
      end

      def new_recursion(ctx, _tc, max_depth, max_leaves)
        @new_recursion_calls << [max_depth, max_leaves]
        LibHegel.check!(self, ctx, @new_recursion_code)
        Object.new
      end

      # Answers the next of #recursion_branch_values, or false once they run
      # out, so a recursive draw against this Fake ends in a leaf.
      def recursion_branch(ctx, _tc, _recursion, _depth)
        LibHegel.check!(self, ctx, @recursion_branch_code)
        @recursion_branch_values.shift || false
      end

      # The next of #recursion_leaf_codes, HEGEL_OK once they run out.
      # HEGEL_E_RETRY answers false, as LibHegel::Real#recursion_leaf does.
      def recursion_leaf(ctx, _tc, _recursion)
        retry_or_check!(ctx, @recursion_leaf_codes.shift || HEGEL_OK)
      end

      # The next of #recursion_retry_codes. Once they run out, HEGEL_OK
      # until the ninth retry of one recursion, which answers
      # HEGEL_E_ASSUME, as libhegel's RECURSION_MAX_ATTEMPTS has it.
      def recursion_retry(ctx, _tc, recursion)
        attempts = @recursion_retries[recursion] += 1
        default = (attempts >= RECURSION_MAX_ATTEMPTS) ? HEGEL_E_ASSUME : HEGEL_OK
        LibHegel.check!(self, ctx, @recursion_retry_codes.shift || default)
        nil
      end

      def recursion_finish(ctx, _tc, _recursion)
        retry_or_check!(ctx, @recursion_finish_codes.shift || HEGEL_OK)
      end

      def recursion_free(_ctx, recursion)
        @freed_recursions << recursion
        nil
      end

      private

      def retry_or_check!(ctx, code)
        return false if code == HEGEL_E_RETRY

        LibHegel.check!(self, ctx, code)
        true
      end
    end
  end
end
