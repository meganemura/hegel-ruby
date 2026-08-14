# frozen_string_literal: true

require "test_helper"
require "hegel/runner"
require "support/fake_lib_hegel"

class TestRunner < Minitest::Test
  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step (Hegel::Runner.run calling hegel_settings_set_database with "")
  # regressed; every test in this class, real-engine and Fake alike, must
  # leave none.
  def teardown
    refute Dir.exist?(File.join(Dir.pwd, ".hegel")),
      "a run must not leave a .hegel directory behind"
  end

  # Exercises the default Hegel::LibHegel::Real wiring end to end: no impl:
  # override, both draw_integer and draw_boolean (with and without its
  # default p), and the verbosity: Symbol mapping against the real engine.
  def test_hegel_test_returns_nil_for_an_always_true_property
    result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
      tc.draw_integer(0, 10)
      tc.draw_boolean
      tc.draw_boolean(0.25)
    end

    assert_nil result
  end

  # Shrinking is real-engine behaviour; Hegel::LibHegel::Fake has no
  # generator or shrinker behind it. n > 500 out of [0, 1_000_000] must
  # shrink to the minimal counterexample, 501, matching the example in the
  # class-level documentation this task's public API follows.
  def test_hegel_test_shrinks_to_the_minimal_counterexample
    error = assert_raises(RuntimeError) do
      Hegel.test(verbosity: :quiet) do |tc|
        n = tc.draw_integer(0, 1_000_000)
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes error.message, "501"
  end

  def test_hegel_test_passes_when_assume_failed_cases_are_mixed_in
    result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
      n = tc.draw_integer(0, 10)
      raise Hegel::AssumeFailed if n.odd?
    end

    assert_nil result
  end

  def test_hegel_test_reraises_the_bodys_exception_class_and_message
    fake = failing_fake_replaying_the_same_body

    error = assert_raises(ZeroDivisionError) do
      Hegel.test(impl: fake) { |_tc| raise ZeroDivisionError, "divided by zero" }
    end

    assert_equal "divided by zero", error.message
  end

  # The library's own control exceptions descend from Exception, not
  # StandardError, precisely so a rescue in the test body cannot swallow
  # them (see lib/hegel/errors.rb). Interrupt must behave the same way:
  # re-raised immediately, never turned into a counterexample, and never
  # reported to hegel_mark_complete.
  def test_interrupt_is_not_treated_as_a_counterexample_and_frees_the_test_case_handle
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1

    assert_raises(Interrupt) { Hegel.test(impl: fake) { |_tc| raise Interrupt } }

    assert_equal 1, fake.freed_test_cases.size
    assert_empty fake.marked_statuses
    assert_equal 1, fake.freed_contexts.size
  end

  # A stale blob's replay overruns (HEGEL_E_STOP_TEST from the draw that no
  # longer matches, per the header), which #classify turns into OVERRUN, not
  # INTERESTING. Re-raising Hegel::StopTest here would leak this library's
  # own control exception into the host test framework -- the exact failure
  # this test exists to rule out.
  def test_replay_ending_in_stop_test_raises_flaky_error_not_stop_test
    calls = 0
    fake = failing_fake_replaying_the_same_body
    body = lambda do |_tc|
      calls += 1
      raise "boom" if calls == 1

      raise Hegel::StopTest, "stale blob"
    end

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake, &body) }

    refute_kind_of Hegel::StopTest, error
    assert_equal 2, calls
  end

  # The other non-reproducing case: replay's body simply returns instead of
  # raising StopTest. Both are "not INTERESTING", the flaky check's actual
  # condition (see Hegel::Runner#replay_failure), not "did not raise".
  def test_replay_without_reproducing_raises_flaky_error_mentioning_external_state
    calls = 0
    fake = failing_fake_replaying_the_same_body
    body = lambda do |_tc|
      calls += 1
      raise "boom" if calls == 1
    end

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake, &body) }

    assert_match(/state|time|random/i, error.message)
    assert_equal 2, calls
  end

  def test_origin_is_stable_for_two_failures_raised_at_the_same_line
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 2

    result = Hegel.test(impl: fake) { |_tc| raise "boom" }

    assert_nil result
    assert_equal 2, fake.marked_origins.size
    first, second = fake.marked_origins
    refute_nil first
    assert_equal first, second
  end

  def test_origin_for_falls_back_to_the_unknown_constant_without_a_backtrace_location
    never_raised = RuntimeError.new("no backtrace yet")
    assert_equal Hegel::Runner::UNKNOWN_ORIGIN, Hegel::Runner.origin_for(never_raised)
  end

  def test_hegel_test_raises_hegel_error_when_the_run_errors
    fake = Hegel::LibHegel::Fake.new
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_ERROR
    fake.run_result_error_value = "a failed health check"

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |_tc| } }

    assert_equal "a failed health check", error.message
  end

  def test_hegel_test_raises_hegel_error_with_a_fallback_message_when_the_run_error_has_none
    fake = Hegel::LibHegel::Fake.new
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_ERROR
    fake.run_result_error_value = nil

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |_tc| } }

    refute_empty error.message
  end

  def test_replay_raises_hegel_error_when_a_failure_has_no_reproduction_blob
    fake = Hegel::LibHegel::Fake.new
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    fake.failure_origins = ["origin.rb:1"]
    fake.failure_blobs = [nil]

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |_tc| } }

    assert_includes error.message, "reproduction blob"
  end

  # hegel_run_status_t values this binding does not recognise (an engine
  # newer than the pinned one) must still be reported, not silently ignored,
  # matching how LibHegel.check! names an unrecognised result code.
  def test_finish_raises_hegel_error_for_an_unrecognized_run_status
    fake = Hegel::LibHegel::Fake.new
    fake.run_result_status_value = 99

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |_tc| } }

    assert_includes error.message, "99"
  end

  private

  # A Fake configured for a FAILED run with exactly one failure whose blob
  # replays through the same +block+ Hegel.test was given, matching how the
  # real engine replays a failure against the caller's own test body.
  def failing_fake_replaying_the_same_body
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    fake.failure_origins = ["origin.rb:1"]
    fake.failure_blobs = ["blob"]
    fake
  end
end
