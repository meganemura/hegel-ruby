# frozen_string_literal: true

require "test_helper"
require "hegel"
require "support/fake_lib_hegel"
require "stringio"

# Hegel::TestCase#repeat. The real-engine tests port hegel-rust's
# tests/test_loop.rs, its snapshots pinned to the report this library
# renders; the Fake tests pin the rescue order and the loop's bookkeeping,
# which the real engine reaches only by chance.
class TestRepeat < Minitest::Test
  include HegelDirectoryGuard

  def teardown
    refute_new_hegel_directory
  end

  def test_loop_fails_on_first_iteration
    lines = failing_report_lines do |tc|
      tc.repeat do
        x = tc.draw(Hegel::Generators.integers)
        raise "too big" unless x < 10
      end
    end

    assert_equal ["// Repetition #1", "  x = 10"], lines
  end

  def test_loop_runs_multiple_iterations_before_failing
    lines = failing_report_lines do |tc|
      count = 0
      tc.repeat do
        count += 1
        raise "three iterations" unless count < 3
      end
    end

    assert_equal ["// Repetition #1", "// Repetition #2", "// Repetition #3"], lines
  end

  def test_loop_with_multiple_draws_per_iteration
    lines = failing_report_lines do |tc|
      tc.repeat do
        x = tc.draw(Hegel::Generators.integers(min_value: 0, max_value: 100))
        y = tc.draw(Hegel::Generators.integers(min_value: 0, max_value: 100))
        raise "sum too big" unless x + y < 5
      end
    end

    assert_equal ["// Repetition #1", "  x = 0", "  y = 5"], lines
  end

  def test_loop_accumulates_state_across_iterations
    lines = failing_report_lines do |tc|
      total = 0
      tc.repeat do
        n = tc.draw(Hegel::Generators.integers(min_value: 1, max_value: 10))
        total += n
        raise "total too big" unless total < 5
      end
    end

    assert_equal ["// Repetition #1", "  n = 5"], lines
  end

  def test_loop_recovers_from_assumption_failures
    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 200, derandomize: true, verbosity: :quiet) do |tc|
        iteration = 0
        successes = 0
        tc.repeat do
          iteration += 1
          tc.assume(false) if iteration.odd?
          successes += 1
          raise "three successes" unless successes < 3
        end
      end
    end
  end

  def test_loop_terminates_when_body_never_fails
    iterations = 0

    result = Hegel.test(test_cases: 3, derandomize: true, verbosity: :quiet) do |tc|
      tc.repeat { iterations += 1 }
    end

    assert_nil result
    assert_operator iterations, :>, 0
  end

  # The loop's minimum length is drawn first and handed to the collection,
  # which has no upper bound; the collection is freed once the loop ends.
  def test_repeat_sizes_the_loop_from_a_drawn_minimum_and_frees_it
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.generate_integer_value = 7
    fake.collection_more_count = 2
    iterations = 0

    Hegel.test(impl: fake) { |tc| tc.repeat { iterations += 1 } }

    assert_equal 2, iterations
    assert_equal 1, fake.opened_collections.size
    collection, min_size, max_size = fake.opened_collections.first
    assert_equal [7, Hegel::LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED], [min_size, max_size]
    assert_equal [collection], fake.freed_collections
    assert_equal [Hegel::LibHegel::HEGEL_STATUS_VALID], fake.marked_statuses
  end

  # A `rescue => e` written around the loop does not see the end of it,
  # because Hegel::LoopDone descends from Exception.
  def test_a_bare_rescue_in_the_body_cannot_swallow_loop_done
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    rescued = nil
    after_loop = false

    Hegel.test(impl: fake) do |tc|
      begin
        tc.repeat {}
      rescue => e
        rescued = e
      end
      after_loop = true
    end

    assert_nil rescued
    refute after_loop
    assert_equal [Hegel::LibHegel::HEGEL_STATUS_VALID], fake.marked_statuses
  end

  def test_runner_classifies_loop_done_as_valid
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |_tc| raise Hegel::LoopDone }

    assert_equal [Hegel::LibHegel::HEGEL_STATUS_VALID], fake.marked_statuses
  end

  # `break` returns from #repeat with the break value, frees the
  # collection, and puts the indent back, so the body goes on after the
  # loop and what it records sits at the outer indent.
  def test_break_ends_the_loop_and_returns_from_repeat
    fake = failing_fake
    fake.collection_more_count = 5
    fake.generate_integer_value = 3
    output = StringIO.new
    iterations = 0
    returned = nil

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, output: output) do |tc|
        returned = tc.repeat do
          iterations += 1
          break :stopped if iterations == 2
        end
        after = tc.draw_integer(0, 10)
        raise "after the loop: #{after}"
      end
    end

    assert_equal :stopped, returned
    assert_equal 2, iterations
    assert_equal fake.opened_collections.map(&:first), fake.freed_collections
    assert_includes output.string, "  // Repetition #2\n  after = 3\n"
  end

  # A failed assumption skips one iteration, not the whole case: the loop
  # runs on, and the case still ends VALID.
  def test_an_assumption_failure_skips_to_the_next_iteration
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.collection_more_count = 3
    iterations = 0

    Hegel.test(impl: fake) do |tc|
      tc.repeat do
        iterations += 1
        tc.reject
      end
    end

    assert_equal 3, iterations
    assert_equal [Hegel::LibHegel::HEGEL_STATUS_VALID], fake.marked_statuses
  end

  # An ordinary failure draws one boolean before it re-raises. The Fake's
  # boolean answers HEGEL_E_STOP_TEST here, so the case ends OVERRUN only
  # if that draw happened.
  def test_a_failure_draws_a_boolean_before_it_re_raises
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.collection_more_count = 1
    fake.generate_boolean_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    Hegel.test(impl: fake) { |tc| tc.repeat { raise "boom" } }

    assert_equal [Hegel::LibHegel::HEGEL_STATUS_OVERRUN], fake.marked_statuses
  end

  # The control exceptions and Hegel::Error re-raise without the boolean
  # draw. The Fake's boolean answers HEGEL_E_INTERNAL here, which would turn
  # each outcome into Hegel::Error, so each status below shows no boolean
  # was drawn.
  def test_control_exceptions_and_hegel_error_re_raise_without_a_draw
    [
      [Hegel::StopTest, Hegel::LibHegel::HEGEL_STATUS_OVERRUN],
      [Hegel::LoopDone, Hegel::LibHegel::HEGEL_STATUS_VALID]
    ].each do |exception, status|
      fake = boolean_failing_fake
      Hegel.test(impl: fake) { |tc| tc.repeat { raise exception } }

      assert_equal [status], fake.marked_statuses, exception.name
    end

    fake = boolean_failing_fake
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    error = assert_raises(Hegel::Error) do
      Hegel.test(impl: fake, output: StringIO.new) { |tc| tc.repeat { raise Hegel::Error, "from the body" } }
    end
    assert_equal "from the body", error.message
  end

  # A nested loop's end is the outer iteration's end too, the same as
  # hegel-rust, where the inner LoopDone unwinds through the outer loop.
  def test_a_nested_loop_ends_the_case_when_it_finishes
    fake = boolean_failing_fake
    fake.collection_more_count = 1
    inner = 0
    after_inner = false

    Hegel.test(impl: fake) do |tc|
      tc.repeat do
        tc.repeat { inner += 1 }
        after_inner = true
      end
    end

    refute after_inner
    assert_equal [Hegel::LibHegel::HEGEL_STATUS_VALID], fake.marked_statuses
  end

  def test_a_fatal_exception_leaves_the_loop_without_a_draw
    fake = boolean_failing_fake

    assert_raises(Interrupt) { Hegel.test(impl: fake) { |tc| tc.repeat { raise Interrupt } } }

    assert_empty fake.marked_statuses
    assert_equal fake.opened_collections.map(&:first), fake.freed_collections
  end

  private

  # The entry lines of the report a failing real-engine run writes: the
  # lines between the "Falsified after" header and the next blank line,
  # without the report's own 2-column indent.
  def failing_report_lines(&body)
    output = StringIO.new
    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 200, derandomize: true, output: output, &body)
    end
    output.string.lines(chomp: true).drop(2).take_while { |line| !line.empty? }.map { |line| line.delete_prefix("  ") }
  end

  def failing_fake
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    fake
  end

  def boolean_failing_fake
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.collection_more_count = 1
    fake.generate_boolean_code = Hegel::LibHegel::HEGEL_E_INTERNAL
    fake
  end
end
