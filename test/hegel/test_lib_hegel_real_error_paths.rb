# frozen_string_literal: true

require "test_helper"
require "hegel/lib_hegel"
require "hegel/lib_hegel/real"

# LibHegel::Real's own error-code translation (LibHegel.check!), pinned
# against the real engine rather than the Fake: test_lib_hegel.rb's own
# real-engine tests all draw a settings handle, a run, and a test case
# through the success path, so none of them observes what happens when
# LibHegel.check! is skipped and a call's out-parameter is read anyway. The
# header states every function returns HEGEL_E_INVALID_HANDLE for a NULL
# handle it requires (other than the *_free functions), which needs no run
# or test case to reach: a NULL settings, test case, run, result, or failure
# handle already exercises it, cheaper than driving a run to a real failure.
class TestLibHegelRealErrorPaths < Minitest::Test
  # Every settings setter and hegel_run_start take the settings handle as
  # their second argument (after ctx); passing NULL for it is the header's
  # own documented HEGEL_E_INVALID_HANDLE case, common to every one of them.
  def test_settings_setters_and_run_start_raise_on_a_nil_settings_handle
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      calls = {
        settings_set_test_cases: -> { real.settings_set_test_cases(ctx, nil, 1) },
        settings_set_verbosity: -> { real.settings_set_verbosity(ctx, nil, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET) },
        settings_set_seed: -> { real.settings_set_seed(ctx, nil, 1, true) },
        settings_set_derandomize: -> { real.settings_set_derandomize(ctx, nil, true) },
        settings_set_database: -> { real.settings_set_database(ctx, nil, "") },
        settings_set_stateful_step_count: -> { real.settings_set_stateful_step_count(ctx, nil, 1) },
        settings_set_report_multiple_failures: -> { real.settings_set_report_multiple_failures(ctx, nil, true) },
        settings_set_database_key: -> { real.settings_set_database_key(ctx, nil, "k") },
        settings_set_phases: -> { real.settings_set_phases(ctx, nil, Hegel::LibHegel::HEGEL_PHASE_ALL) },
        settings_set_suppress_health_check: -> {
          real.settings_set_suppress_health_check(ctx, nil, Hegel::LibHegel::HEGEL_HC_TOO_SLOW)
        },
        run_start: -> { real.run_start(ctx, nil) }
      }

      calls.each do |name, call|
        error = assert_raises(Hegel::Error) { call.call }
        assert_includes error.message, "HEGEL_E_INVALID_HANDLE", "#{name} did not report an invalid handle"
      end
    end
  end

  # Every call below takes a test-case handle. Passing NULL for it is
  # HEGEL_E_INVALID_HANDLE, the same documented case as the settings group
  # above; none of these needs a live run to reach, since the test-case
  # argument is checked before anything else about the call.
  def test_test_case_scoped_calls_raise_on_a_nil_test_case_handle
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      calls = {
        mark_complete: -> { real.mark_complete(ctx, nil, Hegel::LibHegel::HEGEL_STATUS_VALID, nil) },
        generate_boolean: -> { real.generate_boolean(ctx, nil, 0.5, false, false) },
        generate_integer: -> { real.generate_integer(ctx, nil, 0, 1) },
        generate_integer_big: -> { real.generate_integer_big(ctx, nil, 0, 1) },
        generate_float: -> {
          real.generate_float(ctx, nil, 64, 0.0, 1.0, false, false, false, false,
            Hegel::LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED)
        },
        generate_bytes: -> { real.generate_bytes(ctx, nil, 1, 2) },
        generate_ipv4: -> { real.generate_ipv4(ctx, nil) },
        generate_ipv6: -> { real.generate_ipv6(ctx, nil) },
        generate_date: -> { real.generate_date(ctx, nil, [1, 1, 1], [1, 1, 1]) },
        generate_time: -> { real.generate_time(ctx, nil, [0, 0, 0, 0], [0, 0, 0, 0]) },
        generate_datetime: -> { real.generate_datetime(ctx, nil, [1, 1, 1], [0, 0, 0, 0], [1, 1, 1], [0, 0, 0, 0]) },
        start_span: -> { real.start_span(ctx, nil, Hegel::LibHegel::HEGEL_LABEL_TUPLE) },
        stop_span: -> { real.stop_span(ctx, nil, false) },
        new_collection: -> { real.new_collection(ctx, nil, 0, 1) },
        new_pool: -> { real.new_pool(ctx, nil) },
        new_state_machine: -> { real.new_state_machine(ctx, nil, ["a"], []) },
        generate_string: -> { real.generate_string(ctx, nil, nil) },
        collection_more: -> { real.collection_more(ctx, nil, nil) },
        collection_reject: -> { real.collection_reject(ctx, nil, nil) },
        pool_add: -> { real.pool_add(ctx, nil, nil) },
        state_machine_next_rule: -> { real.state_machine_next_rule(ctx, nil, nil) },
        state_machine_rule_rejected: -> { real.state_machine_rule_rejected(ctx, nil, nil) }
      }

      calls.each do |name, call|
        error = assert_raises(Hegel::Error) { call.call }
        assert_includes error.message, "HEGEL_E_INVALID_HANDLE", "#{name} did not report an invalid handle"
      end
    end
  end

  # hegel_next_test_case's own run argument, NULL, the same documented
  # HEGEL_E_INVALID_HANDLE case as the settings and test-case groups above.
  def test_next_test_case_raises_on_a_nil_run_handle
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      error = assert_raises(Hegel::Error) { real.next_test_case(ctx, nil) }
      assert_includes error.message, "HEGEL_E_INVALID_HANDLE"
    end
  end

  # hegel_run_result, its four readers, and hegel_failure_origin /
  # hegel_failure_reproduction_blob each take a run, a run result, or a
  # failure handle; NULL for it is the same documented
  # HEGEL_E_INVALID_HANDLE case the two groups above already exercise, one
  # handle kind at a time.
  def test_run_result_and_failure_calls_raise_on_nil_handles
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      calls = {
        run_result: -> { real.run_result(ctx, nil) },
        run_result_status: -> { real.run_result_status(ctx, nil) },
        run_result_error: -> { real.run_result_error(ctx, nil) },
        run_result_failure_count: -> { real.run_result_failure_count(ctx, nil) },
        run_result_failure: -> { real.run_result_failure(ctx, nil, 0) },
        failure_origin: -> { real.failure_origin(ctx, nil) },
        failure_reproduction_blob: -> { real.failure_reproduction_blob(ctx, nil) }
      }

      calls.each do |name, call|
        error = assert_raises(Hegel::Error) { call.call }
        assert_includes error.message, "HEGEL_E_INVALID_HANDLE", "#{name} did not report an invalid handle"
      end
    end
  end

  # hegel_string_generator_text and hegel_string_generator_regex take no
  # handle beyond ctx, so an invalid argument (an unrecognized codec, an
  # unparsable pattern) is what reaches HEGEL_E_INVALID_ARG for these two,
  # rather than the NULL-handle case the groups above use.
  def test_string_generator_text_and_regex_raise_on_an_invalid_argument
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      text_error = assert_raises(Hegel::Error) do
        real.string_generator_text(ctx, min_size: 1, max_size: 1, codec: "not-a-real-codec")
      end
      assert_includes text_error.message, "HEGEL_E_INVALID_ARG"

      regex_error = assert_raises(Hegel::Error) { real.string_generator_regex(ctx, "(", false) }
      assert_includes regex_error.message, "HEGEL_E_INVALID_ARG"
    end
  end
end
