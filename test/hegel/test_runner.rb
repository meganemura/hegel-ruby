# frozen_string_literal: true

require "test_helper"
require "hegel/runner"
require "support/fake_lib_hegel"
require "stringio"
require "tmpdir"
require "fileutils"

# A tiny object with its own Minitest::Assertions, used to raise an
# assertion failure from an exact, known line in this file rather than from
# somewhere inside Hegel.test's own run loop. #assertions is required by
# Minitest::Assertions#assert; a plain Object lacks it.
class OriginProbe
  include Minitest::Assertions

  attr_accessor :assertions

  def initialize
    @assertions = 0
  end
end

class TestRunner < Minitest::Test
  # A run that leaves ./.hegel behind means Hegel::Settings.apply_database's
  # nil/nil row (the default when a test here passes neither database:
  # keyword) regressed and stopped calling hegel_settings_set_database with
  # "". Every test in this class that does not pass database: itself, real-
  # engine and Fake alike, must leave none; the database-round-trip tests
  # below write into their own Dir.mktmpdir instead, never here.
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
  # hegel-rust's own distinct-failures heading, and #replay raises
  # Hegel::Error carrying that exact same sentence rather than either
  # failure's own exception (see #multiple_failures_message's comment).
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

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake, output: output, &body) }

    assert_equal "Property-based test failed with 2 distinct failures.", error.message
    text = output.string
    assert_includes text, "Property-based test failed with 2 distinct failures."
    assert_includes text, "Falsified after 1 test case (0 discarded):"
    assert_includes text, "Falsified after 2 test cases (0 discarded):"
  end

  # Hegel.test defaults report_multiple_failures: to false and always calls
  # the setter (never skips it the way a nil keyword would), so a caller who
  # passes neither still gets an explicit false, not the engine's own true.
  def test_report_multiple_failures_defaults_to_false_and_is_always_set
    fake = Hegel::LibHegel::Fake.new

    Hegel.test(impl: fake) { |_tc| }

    assert_equal [false], fake.settings_report_multiple_failures_calls
  end

  # report_multiple_failures: true against the real engine: two distinct
  # origins (two different raise lines) both fail, and #replay raises
  # Hegel::Error summarizing the count rather than either origin's own
  # exception.
  def test_report_multiple_failures_true_summarizes_distinct_failures_against_the_real_engine
    body = lambda do |tc|
      n = tc.draw_integer(0, 1, label: "n")
      if n.zero?
        raise "boom-zero"
      else
        raise "boom-one"
      end
    end

    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 10, report_multiple_failures: true, verbosity: :quiet, output: StringIO.new, &body)
    end

    assert_includes error.message, "2 distinct failures"
  end

  # The bug docs/adr/0012 fixes, proven end to end against the real engine:
  # assert_equal raises from inside minitest itself, at the same line
  # (minitest/assertions.rb:176) no matter which of the caller's own lines
  # called it. Before that ADR's fix, Hegel::Runner.origin_for built the
  # origin from that shared minitest line, so both branches below grouped as
  # one bug and libhegel reported a single failure -- Minitest::Assertion
  # itself, unwrapped, rather than Hegel::Error. After the fix, the origin
  # comes from this test's own two `assert_equal` lines, which differ, so
  # the two branches are two distinct failures.
  def test_two_assertion_failures_from_different_lines_report_as_two_distinct_failures
    body = lambda do |tc|
      n = tc.draw_integer(0, 1, label: "n")
      if n.zero?
        assert_equal 0, 1
      else
        assert_equal 0, 2
      end
    end

    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 10, report_multiple_failures: true, verbosity: :quiet, output: StringIO.new, &body)
    end

    assert_includes error.message, "2 distinct failures"
  end

  # The default (false), same body, same real engine: the run still finds
  # both origins, but re-raises only the first origin's own exception class,
  # not a summary -- the behaviour this task's decision (a) exists for.
  def test_report_multiple_failures_false_reraises_the_bodys_own_exception_class
    body = lambda do |tc|
      n = tc.draw_integer(0, 1, label: "n")
      if n.zero?
        raise "boom-zero"
      else
        raise "boom-one"
      end
    end

    error = assert_raises(RuntimeError) do
      Hegel.test(test_cases: 10, verbosity: :quiet, output: StringIO.new, &body)
    end

    assert_match(/boom-(zero|one)/, error.message)
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

  # The bug docs/adr/0012 fixes, isolated to Hegel::Runner.origin_for
  # directly: Minitest::Assertions#assert raises from the same line inside
  # minitest (minitest/assertions.rb:176) for both calls below, but the
  # origin must still tell them apart, because they come from different
  # lines in the caller's own code -- this test file.
  def test_origin_for_returns_distinct_origins_for_assertions_failing_on_different_lines
    probe = OriginProbe.new

    first_error = assert_raises(Minitest::Assertion) { probe.assert_equal(0, 1) }
    second_error = assert_raises(Minitest::Assertion) { probe.assert_equal(0, 2) }

    first_origin = Hegel::Runner.origin_for(first_error)
    second_origin = Hegel::Runner.origin_for(second_error)

    refute_equal first_origin, second_origin
    assert_includes first_origin, File.basename(__FILE__)
    assert_includes second_origin, File.basename(__FILE__)
  end

  # rspec-expectations is not in the Gemfile (adding it needs the user's own
  # confirmation), so this proves the property RSpec's own raise from inside
  # rspec-support would exercise without RSpec itself: a real file written
  # under an installed gem's own "gems/" directory, then raised from. Doing
  # this with a real file, rather than reusing minitest's own frames, proves
  # the rule is general -- any installed gem -- not merely "happens to work
  # for minitest", which is the risk docs/adr/0012 names directly (a list of
  # framework names is "wrong by omission the day someone uses a framework
  # nobody added").
  def test_origin_for_skips_a_frame_under_an_installed_gem_directory
    fixture_dir = File.join(Gem.path.first, "gems", "hegel-origin-fixture-#{Process.pid}")
    fixture_path = File.join(fixture_dir, "raiser.rb")
    FileUtils.mkdir_p(fixture_dir)
    File.write(fixture_path, "def raise_from_hegel_origin_fixture\n  raise \"boom from an installed gem\"\nend\n")

    begin
      load fixture_path
      error = assert_raises(RuntimeError) { raise_from_hegel_origin_fixture }
      # Confirms the fixture actually raises from the gem directory before
      # asking origin_for to skip it -- otherwise a false pass would prove
      # nothing.
      assert_equal fixture_path, error.backtrace_locations.first.path

      origin = Hegel::Runner.origin_for(error)

      refute_includes origin, fixture_dir
      assert_includes origin, File.basename(__FILE__)
    ensure
      FileUtils.rm_rf(fixture_dir)
    end
  end

  # #origin_for must skip this library's own frame the same way it skips a
  # gem's: Hegel::TestCase#note raises from lib/hegel/test_case.rb, one
  # frame below the call this test makes directly.
  def test_origin_for_skips_this_librarys_own_frame
    tc = Hegel::TestCase.new(nil, nil, nil, record: false)

    error = assert_raises(Hegel::Error) { tc.note }

    origin = Hegel::Runner.origin_for(error)

    refute_includes origin, File.join("lib", "hegel", "test_case.rb")
    assert_includes origin, File.basename(__FILE__)
  end

  # When every frame belongs to this library, an installed gem, or the
  # standard library, #origin_for falls back to the first frame rather than
  # UNKNOWN_ORIGIN -- a coarse origin still groups failures consistently,
  # where no origin at all would lose the failure's identity entirely (see
  # docs/adr/0012). Trims a real assertion failure's own backtrace down to
  # just its infrastructure frames (minitest itself already supplies more
  # than one) to build a case with no caller frame at all.
  def test_origin_for_falls_back_to_the_first_frame_when_every_frame_is_infrastructure
    probe = OriginProbe.new
    error = assert_raises(Minitest::Assertion) { probe.assert_equal(0, 1) }
    infrastructure_frames = error.backtrace_locations.select { |location| Hegel::Runner.infrastructure?(location.path) }
    refute_empty infrastructure_frames
    error.set_backtrace(infrastructure_frames)

    origin = Hegel::Runner.origin_for(error)

    first = infrastructure_frames.first
    assert_equal "Raised at #{first.path}:#{first.lineno}", origin
  end

  # #infrastructure? is an OR of three checks; each of the four tests below
  # drives one combination of true/false through it so every branch is
  # covered directly, rather than relying on origin_for's own tests (above)
  # to happen to exercise all three by accident.
  def test_infrastructure_recognizes_this_librarys_own_directory
    assert Hegel::Runner.infrastructure?(File.join(Hegel::Runner::LIBRARY_DIR, "runner.rb"))
  end

  def test_infrastructure_recognizes_an_installed_gem_directory
    path = File.join(Hegel::Runner::INSTALLED_GEM_DIRS.first, "some-gem-1.0.0", "lib", "some_gem.rb")
    assert Hegel::Runner.infrastructure?(path)
  end

  def test_infrastructure_recognizes_the_standard_library_directory
    assert Hegel::Runner.infrastructure?(File.join(Hegel::Runner::STDLIB_DIR, "set.rb"))
  end

  def test_infrastructure_returns_false_for_a_path_outside_every_known_directory
    refute Hegel::Runner.infrastructure?(__FILE__)
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

  # The nil/nil row of Hegel::Settings.apply_database's table, confirmed
  # through the Fake rather than the filesystem: a run given neither
  # database keyword passes "" to settings_set_database and never calls
  # settings_set_database_key at all.
  def test_database_keywords_left_nil_pass_an_empty_string_and_call_no_key_setter
    fake = Hegel::LibHegel::Fake.new

    Hegel.test(impl: fake) { |_tc| }

    assert_equal [""], fake.settings_database_calls
    assert_empty fake.settings_database_key_calls
  end

  # database_key: alone (the row a caller reaches without a database:
  # directory) calls settings_set_database_key and never
  # settings_set_database, so the engine's own default path applies.
  def test_database_key_alone_calls_only_settings_set_database_key
    fake = Hegel::LibHegel::Fake.new

    Hegel.test(impl: fake, database_key: "a-property") { |_tc| }

    assert_empty fake.settings_database_calls
    assert_equal ["a-property"], fake.settings_database_key_calls
  end

  # database: without database_key: raises before the run starts, per
  # docs/adr/0009's table -- caught here through the Fake, so no real run
  # loop or file I/O is needed to prove it.
  def test_database_without_database_key_raises_hegel_error
    fake = Hegel::LibHegel::Fake.new

    error = assert_raises(Hegel::Error) { Hegel.test(impl: fake, database: "/tmp/wherever") { |_tc| } }

    assert_includes error.message, "hegel: "
    assert_includes error.message, "database_key"
  end

  # The real round trip docs/adr/0009 measured: a keyed run against an
  # absolute Dir.mktmpdir path (no Dir.chdir needed) writes into that
  # directory, and a second run against the same path and key replays the
  # stored failure. The body is called twice on that second run, not once:
  # once live, as the run's only drawn test case (see the "Falsified after 1
  # test case" assertion below, which is the ADR's own "first and only test
  # case" claim read off the printed report), and once more during
  # Hegel::Runner#replay_failure's own mandatory final replay, which every
  # failure goes through regardless of the database to build its report
  # entries and re-raise the body's own exception (see #replay's comment).
  # Measured directly against libhegel 0.32.5 before writing this assertion,
  # exactly matching what is asserted here.
  def test_database_round_trip_replays_the_stored_failure_as_the_only_drawn_case_on_the_second_run
    Dir.mktmpdir do |dir|
      body = lambda do |tc|
        tc.draw_integer(0, 10)
        raise "boom"
      end

      assert_raises(RuntimeError) do
        Hegel.test(test_cases: 10, database: dir, database_key: "round-trip", verbosity: :quiet,
          output: StringIO.new, &body)
      end
      refute_empty Dir.children(dir), "the first run must have written into the database directory"

      second_calls = 0
      second_output = StringIO.new
      counting_body = lambda do |tc|
        second_calls += 1
        body.call(tc)
      end

      assert_raises(RuntimeError) do
        Hegel.test(test_cases: 10, database: dir, database_key: "round-trip", output: second_output,
          &counting_body)
      end

      assert_equal 2, second_calls
      assert_includes second_output.string, "Falsified after 1 test case (0 discarded):"
    end
  end

  # Each keyword's own PHASE_CODES/HEALTH_CHECK_CODES bit-OR logic already
  # has Fake coverage in test_settings.rb; these two confirm the same bits
  # reach a real run without erroring, which a Fake cannot show.
  #
  # suppress_health_check: [:filter_too_much] against a property that
  # rejects nearly every case: unsuppressed, libhegel's own FilterTooMuch
  # health check turns the run into an ERROR (Hegel::Error) after 50
  # rejections; suppressed, the same property runs to completion. test_cases
  # is kept small (20) because Hegel::AssumeFailed / #reject cases do not
  # count against that budget (see docs/adr's own measurement, 560 draws for
  # this same shape), so a larger budget would only cost more wall time
  # without exercising a different branch.
  def test_suppress_health_check_filter_too_much_against_the_real_engine
    body = lambda do |tc|
      n = tc.draw_integer(0, 1_000_000)
      tc.reject unless n.zero?
    end

    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 20, verbosity: :quiet, output: StringIO.new, &body)
    end
    assert_includes error.message, "FilterTooMuch"

    result = Hegel.test(test_cases: 20, suppress_health_check: [:filter_too_much], verbosity: :quiet,
      output: StringIO.new, &body)
    assert_nil result
  end

  # phases: [:generate] against the real engine: the header documents a
  # dropped phase as a no-op rather than an error (measured directly: a run
  # missing HEGEL_PHASE_TARGET still returns HEGEL_OK from its first
  # hegel_target call), so this only asserts the run completes -- not that
  # shrinking narrowed the counterexample, since HEGEL_PHASE_SHRINK is one
  # of the phases left out here.
  def test_phases_generate_only_against_the_real_engine
    error = assert_raises(RuntimeError) do
      Hegel.test(test_cases: 10, phases: [:generate], verbosity: :quiet, output: StringIO.new) do |tc|
        tc.draw_integer(0, 1_000_000)
        raise "boom"
      end
    end

    assert_equal "boom", error.message
  end

  # Targeting drives the observed maximum of two [0, 1000] draws' sum up to
  # its ceiling, 2000, without any failure -- the same shape as hegel-rust's
  # own test_can_target_a_score_upwards_without_failing
  # (tests/test_targeting.rs), against the same engine underneath. A
  # comparison run that fails past a threshold instead, with and without
  # #target, does not tell targeting apart from luck: measured 10 runs each
  # way at a fixed threshold, the mean case count before the first failure
  # was 40.4 with #target called and 40.0 without, no distinguishable
  # difference. Reaching a fixed ceiling has no such ambiguity, so this
  # shape is deterministic instead. Run 5 times here, at test_cases: 1000
  # (matching hegel-rust's own test_cases(1000)) to confirm it does not
  # flake.
  def test_target_climbs_a_summed_score_to_its_maximum
    5.times do
      max_score = 0

      result = Hegel.test(test_cases: 1000, verbosity: :quiet, output: StringIO.new) do |tc|
        n = tc.draw_integer(0, 1000)
        m = tc.draw_integer(0, 1000)
        score = n + m
        tc.target(score)
        max_score = score if score > max_score
      end

      assert_nil result
      assert_equal 2000, max_score
    end
  end

  # label: reaches the engine and does not disturb an otherwise-passing run.
  def test_target_accepts_a_label
    result = Hegel.test(test_cases: 20, verbosity: :quiet, output: StringIO.new) do |tc|
      n = tc.draw_integer(0, 1000)
      tc.target(n, label: "score")
    end

    assert_nil result
  end

  # hegel_target's own HEGEL_E_INVALID_ARG for a label recorded twice
  # reaches the caller as Hegel::Error, translated by
  # Hegel::LibHegel.check! the same way as every other invalid argument
  # this library passes through. Raised from inside the body, it is a
  # StandardError descendant, so Hegel::Runner.classify treats it as an
  # ordinary counterexample and re-raises it unaltered once the run
  # finishes -- the same path #classify's own comment documents for a
  # test-body assertion failure.
  def test_target_with_a_repeated_label_raises
    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 5, verbosity: :quiet, output: StringIO.new) do |tc|
        tc.target(1, label: "score")
        tc.target(2, label: "score")
      end
    end

    assert_includes error.message, "at most once per test case"
  end

  # Two distinct labels on the same test case are two distinct
  # observations to the engine, not a conflict.
  def test_target_with_two_different_labels_both_succeed
    result = Hegel.test(test_cases: 5, verbosity: :quiet, output: StringIO.new) do |tc|
      tc.target(1, label: "a")
      tc.target(2, label: "b")
    end

    assert_nil result
  end

  # hegel_target's own "requires a finite score" HEGEL_E_INVALID_ARG for
  # Float::NAN, reaching the caller the same way a repeated label does.
  def test_target_with_a_non_finite_value_raises
    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 5, verbosity: :quiet, output: StringIO.new) do |tc|
        tc.target(Float::NAN)
      end
    end

    assert_includes error.message, "finite"
  end

  # The header documents hegel_target as a no-op unless HEGEL_PHASE_TARGET
  # is enabled, not an error; dropping that one phase from the mask (every
  # other phase kept) must leave #target callable and the run passing.
  def test_target_is_a_no_op_when_the_target_phase_is_dropped
    result = Hegel.test(test_cases: 10, phases: [:explicit, :reuse, :generate, :shrink], verbosity: :quiet,
      output: StringIO.new) do |tc|
      n = tc.draw_integer(0, 1000)
      tc.target(n)
    end

    assert_nil result
  end

  # Hegel::TestCase#new_pool records the native handle it opens, and
  # Hegel::Runner is supposed to free every one of them once the test case
  # that opened it is done -- docs/adr/0011's ownership decision, at the
  # generation-loop path (#run_case).
  def test_run_case_frees_every_pool_the_test_case_opened
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |tc| tc.new_pool }

    assert_equal 1, fake.freed_pools.size
  end

  # A pool opened by a test case that never created one must call
  # hegel_pool_free zero times, not skip a check that would have caught a
  # spurious call -- proves #free_pools iterates an empty list rather than,
  # say, freeing a leftover handle from a previous case.
  def test_run_case_calls_no_pool_free_when_the_test_case_opened_no_pool
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |_tc| }

    assert_empty fake.freed_pools
  end

  # Two pools opened in the same test case must both be freed, not just the
  # first or the last -- #free_pools iterates every recorded handle, not one.
  def test_run_case_frees_two_pools_opened_in_the_same_test_case
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1

    Hegel.test(impl: fake) do |tc|
      tc.new_pool
      tc.new_pool
    end

    assert_equal 2, fake.freed_pools.size
  end

  # #with_test_case releases pools and the test-case handle in nested
  # `ensure`s so one failing release cannot skip the other. Freeing pools
  # first is the order docs/adr/0011 asks for, and a raise there would
  # otherwise carry straight past hegel_test_case_free -- which
  # hegel_context_free then refuses to work around, since it requires every
  # handle taken from the context to be freed first. One skipped release
  # would fail the context's own release at the end of the run.
  def test_a_raise_while_freeing_pools_still_frees_the_test_case_handle
    fake = Class.new(Hegel::LibHegel::Fake) do
      def pool_free(_ctx, _pool)
        raise Hegel::Error, "hegel: pool_free failed"
      end
    end.new
    fake.test_case_count = 1

    assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |tc| tc.new_pool } }

    refute_empty fake.freed_test_cases
  end

  # The replay path (#replay_failure) opens its own Hegel::TestCase from the
  # reproduction blob, distinct from the one the live loop used -- so this
  # counts 2 freed pools, one from #run_case's own live case (calls == 1)
  # and one from the replay (calls == 2), not just the replay's.
  def test_replay_failure_frees_every_pool_the_replayed_test_case_opened
    fake = failing_fake_replaying_the_same_body
    calls = 0
    body = lambda do |tc|
      calls += 1
      tc.new_pool
      raise "boom"
    end

    assert_raises(RuntimeError) { Hegel.test(impl: fake, &body) }

    assert_equal 2, calls
    assert_equal 2, fake.freed_pools.size
  end

  # reproduce_failure: skips the run loop entirely (#reproduce), so this is
  # the one path where a single body call is the whole story.
  def test_reproduce_failure_frees_every_pool_the_reproduced_test_case_opened
    fake = Hegel::LibHegel::Fake.new

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, reproduce_failure: "blob") do |tc|
        tc.new_pool
        raise "boom"
      end
    end

    assert_equal 1, fake.freed_pools.size
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
