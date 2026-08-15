# frozen_string_literal: true

require "test_helper"
require "hegel/runner"
require "support/fake_lib_hegel"
require "stringio"

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
  # class-level documentation this task's public API follows. The captured
  # report must name that same 501 under its label:, and its "Falsified
  # after" count must be the generation phase's own count (bounded by the
  # default 100 test_cases), not the ~1000-iteration shrink phase #drive's
  # own comment measured for a similarly sized run.
  def test_hegel_test_shrinks_to_the_minimal_counterexample_and_reports_it
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        n = tc.draw_integer(0, 1_000_000, label: "n")
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes error.message, "501"

    report = output.string
    assert_includes report, "n = 501"
    falsified_after = report[/Falsified after (\d+) test cases/, 1]
    refute_nil falsified_after
    assert_operator falsified_after.to_i, :<=, 100
  end

  # Same shrink target as above, without label:, exercising Hegel::DrawName
  # recovering the local variable a draw was assigned to from the caller's
  # own source (see docs/adr/0005 and Hegel::TestCase#name_for).
  def test_report_names_an_unlabelled_draw_from_the_variable_it_was_assigned_to
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        n = tc.draw_integer(0, 1_000_000)
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes output.string, "n = 501"
  end

  # An enclosing assignment covers the draw's line too, and a reader still
  # has no doubt which name belongs to the draw, so the innermost one wins
  # (see Hegel::DrawName.for). This shape is not contrived: `error =
  # assert_raises do ... end` here, and RSpec's `expect { ... }` assigned to
  # a variable, both put a whole test body inside one assignment.
  def test_report_names_a_draw_wrapped_in_an_enclosing_assignment
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        n = tc.draw_integer(0, 1_000_000)
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes error.message, "501"
    assert_includes output.string, "n = 501"
  end

  # The "draw" fallback itself (see Hegel::TestCase#name_for): a draw whose
  # result is never assigned to anything has no name Hegel::DrawName could
  # recover, label: or otherwise.
  def test_report_falls_back_to_a_generic_name_when_a_draw_is_not_assigned
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        tc.draw_integer(0, 1_000_000)
        raise "boom"
      end
    end

    assert_match(/draw = \d+/, output.string)
  end

  # label: must win even when Hegel::DrawName could recover a different
  # name from the same line -- the decided order (see Hegel::TestCase#name_for).
  def test_label_wins_over_the_recovered_variable_name
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        value = tc.draw_integer(0, 1_000_000, label: "n")
        raise "too big: #{value}" if value > 500
      end
    end

    report = output.string
    assert_includes report, "n = 501"
    refute_includes report, "value ="
  end

  # Two unlabelled draws assigned on the same line: Hegel::DrawName.for
  # finds two assignment nodes covering that line and refuses to guess
  # which draw either name belongs to, so both fall back to "draw" the same
  # way an unassigned draw does (see test_report_suffixes_two_draws_that_
  # share_the_same_fallback_name below for that other cause of the same
  # fallback).
  def test_two_draws_assigned_on_the_same_line_both_fall_back_to_a_generic_name
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        # standard:disable Style/Semicolon -- both draws must share this one
        # line, not two, for Hegel::DrawName.for to see two assignment nodes
        # covering the same lineno.
        a = tc.draw_integer(0, 10); b = tc.draw_integer(0, 10)
        # standard:enable Style/Semicolon
        raise "boom" if a >= 0 && b >= 0
      end
    end

    report = output.string
    assert_match(/draw_1 = \d+/, report)
    assert_match(/draw_2 = \d+/, report)
    refute_includes report, "a ="
    refute_includes report, "b ="
  end

  # Two unlabelled draws in the one failing case both fall back to "draw";
  # Hegel::Report.assign_names must suffix both, not just report "draw"
  # twice. The body raises unconditionally, so the first generated case is
  # already the failure and both draws always happen.
  def test_report_suffixes_two_draws_that_share_the_same_fallback_name
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        tc.draw_integer(0, 10)
        tc.draw_integer(0, 10)
        raise "boom"
      end
    end

    report = output.string
    assert_match(/draw_1 = \d+/, report)
    assert_match(/draw_2 = \d+/, report)
  end

  # InstanceVariableWriteNode is the other assignment shape Hegel::DrawName
  # recovers a name from; #name already includes the leading "@".
  def test_report_names_an_instance_variable_draw
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        @n = tc.draw_integer(0, 1_000_000)
        raise "too big: #{@n}" if @n > 500
      end
    end

    assert_includes output.string, "@n = 501"
  end

  # A method chain still names the draw after its own assignment target,
  # not the chain's final result: the recorded value is the drawn integer
  # itself (see Hegel::TestCase#record_draw), not xs.to_s's String.
  def test_report_names_a_draw_behind_a_method_chain
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        xs = tc.draw_integer(0, 1_000_000).to_s
        raise "too big: #{xs}" if xs.to_i > 500
      end
    end

    assert_includes output.string, "xs = 501"
  end

  # tc.draw(generator) must recover a name from the caller's own source the
  # same way tc.draw_integer does (see Hegel::TestCase#draw and
  # DRAW_CALLER_DEPTH's own comment), even though a Hegel::Generator's own
  # #do_draw sits between the two.
  def test_report_names_a_draw_made_through_tc_draw
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        n = tc.draw(Hegel::Generators.integers(min_value: 0, max_value: 1_000_000))
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes output.string, "n = 501"
  end

  # #name_for's own caller_locations call returns nil when the stack is
  # shallower than DRAW_CALLER_DEPTH -- a case no real draw_* call site
  # produces (see Hegel::TestCase#name_for), reached directly here the same
  # way test_origin_for_falls_back_to_the_unknown_constant_without_a_
  # backtrace_location below exercises Runner.origin_for's own defensive
  # branch directly.
  def test_name_for_falls_back_to_the_generic_name_when_the_stack_is_too_shallow
    tc = Hegel::TestCase.new(nil, nil, nil, record: true)

    assert_equal Hegel::TestCase::DEFAULT_DRAW_NAME, tc.send(:name_for, nil, 1_000_000)
  end

  # verbosity: :quiet must silence the failure report itself (hegel-rust
  # does the same), not just libhegel's own progress output.
  def test_quiet_verbosity_suppresses_the_report
    fake = failing_fake_replaying_the_same_body
    output = StringIO.new

    assert_raises(ZeroDivisionError) do
      Hegel.test(impl: fake, verbosity: :quiet, output: output) { |_tc| raise ZeroDivisionError, "divided by zero" }
    end

    assert_empty output.string
  end

  # M ("discarded") must count only the Hegel::AssumeFailed cases seen
  # before the origin that ends up reported first went INTERESTING, not
  # every case #drive ever sees.
  def test_report_discarded_count_matches_the_assume_failed_calls_before_the_failure
    fake = failing_fake_replaying_the_same_body
    fake.test_case_count = 3
    calls = 0
    body = lambda do |_tc|
      calls += 1
      raise Hegel::AssumeFailed if calls <= 2
      raise "boom"
    end
    output = StringIO.new

    assert_raises(RuntimeError) { Hegel.test(impl: fake, output: output, &body) }

    assert_includes output.string, "Falsified after 3 test cases (2 discarded):"
  end

  # Two origins, both discovered live by #drive (so Hegel::Runner::
  # GenerationStats has a snapshot for each before #replay asks), get
  # hegel-rust's own distinct-failures heading.
  def test_report_shows_a_heading_when_there_are_multiple_distinct_failures
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 2
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 2
    fake.failure_origins = ["unused-a", "unused-b"]
    fake.failure_blobs = ["blob-a", "blob-b"]
    calls = 0
    body = lambda do |_tc|
      calls += 1
      if calls.odd?
        raise "boom-a"
      else
        raise "boom-b"
      end
    end
    output = StringIO.new

    assert_raises(RuntimeError) { Hegel.test(impl: fake, output: output, &body) }

    text = output.string
    assert_includes text, "Property-based test failed with 2 distinct failures."
    assert_includes text, "Falsified after 1 test case (0 discarded):"
    assert_includes text, "Falsified after 2 test cases (0 discarded):"
  end

  # The end-to-end proof this report is honest: a blob it printed, fed back
  # unchanged, must replay the very failure it came from against the real
  # engine.
  def test_reproduce_failure_replays_the_printed_blob_against_the_real_engine
    output = StringIO.new
    body = lambda do |tc|
      n = tc.draw_integer(0, 1_000_000, label: "n")
      raise "too big: #{n}" if n > 500
    end

    first_error = assert_raises(RuntimeError) { Hegel.test(output: output, &body) }

    blob = output.string[/reproduce_failure: "(.+)"/, 1]
    refute_nil blob

    reproduce_output = StringIO.new
    second_error = assert_raises(RuntimeError) do
      Hegel.test(reproduce_failure: blob, output: reproduce_output, &body)
    end

    assert_equal first_error.message, second_error.message
    assert_includes reproduce_output.string, "n = 501"
  end

  # Hegel::Runner.reproduce records with record: true the same way
  # #replay_failure does; a note must reach its report through that path
  # too, not only through the live loop's own replay.
  def test_reproduce_failure_replays_a_note_against_the_real_engine
    output = StringIO.new
    body = lambda do |tc|
      n = tc.draw_integer(0, 1_000_000, label: "n")
      tc.note("n was #{n}")
      raise "too big: #{n}" if n > 500
    end

    assert_raises(RuntimeError) { Hegel.test(output: output, &body) }

    blob = output.string[/reproduce_failure: "(.+)"/, 1]
    refute_nil blob

    reproduce_output = StringIO.new
    assert_raises(RuntimeError) { Hegel.test(reproduce_failure: blob, output: reproduce_output, &body) }

    assert_includes reproduce_output.string, "n was 501"
  end

  # verbosity: :quiet must silence #reproduce's own report the same way it
  # silences #replay's (see test_quiet_verbosity_suppresses_the_report).
  def test_reproduce_failure_respects_quiet_verbosity
    fake = Hegel::LibHegel::Fake.new
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, reproduce_failure: "blob", verbosity: :quiet, output: output) { |_tc| raise "boom" }
    end

    assert_empty output.string
  end

  # hegel_test_case_from_blob itself documents HEGEL_E_STOP_TEST for "a
  # blob whose choices no longer match the caller's generators" -- staleness
  # caught at construction, before any draw call runs. Hegel::Runner.reproduce
  # must not let that leak as Hegel::StopTest.
  def test_reproduce_failure_with_a_stale_blob_raises_hegel_error_at_construction
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_from_blob_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    error = assert_raises(Hegel::Error) do
      Hegel.test(impl: fake, reproduce_failure: "stale-blob") { |_tc| }
    end

    refute_kind_of Hegel::StopTest, error
  end

  # The other manifestation of the same staleness: construction succeeds,
  # but a draw call against the mismatched blob raises Hegel::StopTest (the
  # same code #classify already turns into OVERRUN for the live loop).
  def test_reproduce_failure_with_a_stale_blob_raises_hegel_error_at_draw_time
    fake = Hegel::LibHegel::Fake.new

    error = assert_raises(Hegel::Error) do
      Hegel.test(impl: fake, reproduce_failure: "stale-blob") { |_tc| raise Hegel::StopTest, "stale blob" }
    end

    refute_kind_of Hegel::StopTest, error
  end

  def test_hegel_test_passes_when_assume_failed_cases_are_mixed_in
    result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
      n = tc.draw_integer(0, 10)
      raise Hegel::AssumeFailed if n.odd?
    end

    assert_nil result
  end

  # tc.assume(false) discards the case the same way raising
  # Hegel::AssumeFailed directly does (see the precedent test above), but
  # through the public entry point, against the real engine. A call
  # counter, not the drawn value, decides which cases discard, so
  # libhegel's own randomness cannot make this test flaky: the origin only
  # ever goes INTERESTING at call 3, and Hegel::Runner::GenerationStats
  # snapshots its first appearance, so extra generation or shrink calls
  # afterward (both keep raising, since the counter has already passed 2)
  # cannot move the reported count.
  #
  # The draw is required, not decoration: measured against libhegel 0.32.5,
  # a case that discards having drawn nothing carries no choices to vary,
  # so the run treats it as fully determined and stops after that one
  # trial (PASSED) instead of pulling another test case.
  def test_assume_false_discards_the_case_and_counts_toward_discarded
    output = StringIO.new
    calls = 0
    body = lambda do |tc|
      calls += 1
      tc.draw_integer(0, 10)
      tc.assume(false) if calls <= 2
      raise "boom"
    end

    assert_raises(RuntimeError) { Hegel.test(output: output, &body) }

    assert_includes output.string, "Falsified after 3 test cases (2 discarded):"
  end

  # tc.reject discards unconditionally, the same shape as tc.assume(false)
  # above (see its comment for why the draw is required).
  def test_reject_discards_the_case_and_counts_toward_discarded
    output = StringIO.new
    calls = 0
    body = lambda do |tc|
      calls += 1
      tc.draw_integer(0, 10)
      tc.reject if calls <= 2
      raise "boom"
    end

    assert_raises(RuntimeError) { Hegel.test(output: output, &body) }

    assert_includes output.string, "Falsified after 3 test cases (2 discarded):"
  end

  # tc.assume(true) is a no-op: nothing is discarded, so an always-true
  # property still passes, against the real engine.
  def test_assume_true_does_not_discard_the_case
    result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
      tc.assume(true)
      tc.draw_integer(0, 10)
    end

    assert_nil result
  end

  # A note's message appears in the failure report interleaved with draws
  # in call order, matching Hegel::TestCase's own class-level documentation
  # example (a note, a draw, then a conditional note).
  def test_note_appears_in_the_failure_report_interleaved_with_draws_in_call_order
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        tc.note("starting the queue")
        n = tc.draw_integer(0, 1_000_000, label: "n")
        tc.note("queue was empty") if n > 500
        raise "too big: #{n}" if n > 500
      end
    end

    assert_includes output.string, "starting the queue\n  n = 501\n  queue was empty"
  end

  # The block form is only evaluated on the one, already-shrunk replay that
  # produces the report (see Hegel::TestCase#note): every other iteration
  # of a failing run like this one -- roughly 1000, per Hegel::Runner.drive's
  # own comment -- skips the block entirely, so the counter below reads 1.
  def test_note_block_form_evaluates_exactly_once_on_the_final_replay
    calls = 0
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        n = tc.draw_integer(0, 1_000_000, label: "n")
        tc.note do
          calls += 1
          "n was #{n}"
        end
        raise "too big: #{n}" if n > 500
      end
    end

    assert_equal 1, calls
    assert_includes output.string, "n was 501"
  end

  # A failure can be reported with no draws at all, only notes.
  def test_note_reports_a_failure_with_no_draws
    fake = failing_fake_replaying_the_same_body
    output = StringIO.new
    body = lambda do |tc|
      tc.note("only a note")
      raise "boom"
    end

    assert_raises(RuntimeError) { Hegel.test(impl: fake, output: output, &body) }

    assert_includes output.string, "  only a note"
  end

  # Argument validation runs before the #@record check, so a caller's
  # mistake surfaces on every call, not only the one iteration that
  # happens to record (see Hegel::TestCase#note). record: false here is
  # that non-recording iteration, exercised directly.
  def test_note_with_neither_message_nor_block_raises_even_when_not_recording
    tc = Hegel::TestCase.new(nil, nil, nil, record: false)

    error = assert_raises(Hegel::Error) { tc.note }

    assert_includes error.message, "exactly one"
  end

  # The other invalid combination: both a message and a block.
  def test_note_with_both_message_and_block_raises_even_when_not_recording
    tc = Hegel::TestCase.new(nil, nil, nil, record: false)

    error = assert_raises(Hegel::Error) { tc.note("x") { "y" } }

    assert_includes error.message, "exactly one"
  end

  def test_hegel_test_reraises_the_bodys_exception_class_and_message
    fake = failing_fake_replaying_the_same_body

    error = assert_raises(ZeroDivisionError) do
      Hegel.test(impl: fake, output: StringIO.new) { |_tc| raise ZeroDivisionError, "divided by zero" }
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
