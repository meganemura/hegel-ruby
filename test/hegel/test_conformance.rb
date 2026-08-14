# frozen_string_literal: true

require "test_helper"
require "support/conformance"

class TestConformance < Minitest::Test
  include Hegel::Conformance
  include Hegel::Syntax::Methods

  # Same regression this module's own callers rely on (see
  # TestGenerators#teardown): a run must not leave ./.hegel behind, and
  # every test below drives a real Hegel.test run through these helpers.
  def teardown
    refute Dir.exist?(File.join(Dir.pwd, ".hegel")),
      "a run must not leave a .hegel directory behind"
  end

  def test_assert_all_examples_passes_when_every_value_satisfies_the_block
    assert_all_examples(integers(min_value: 0, max_value: 10)) { |n| n.between?(0, 10) }
  end

  # The predicate never holds, so every draw fails and the run shrinks to
  # the smallest possible counterexample, 0 -- deterministic, unlike a
  # predicate that only sometimes fails, which would only sometimes shrink
  # to a value this assertion could pin down.
  def test_assert_all_examples_fails_with_the_failing_value_in_the_message
    error = assert_raises(Minitest::Assertion) do
      assert_all_examples(integers(min_value: 0, max_value: 10)) { |n| n > 10 }
    end

    assert_includes error.message, "predicate failed for: 0"
  end

  # capture_subprocess_io redirects the real file descriptors, not just
  # Ruby's $stderr object, so this also covers libhegel's own native-side
  # output -- verbosity: :quiet's job -- not just this module's Ruby-level
  # Discard seal on output:.
  def test_assert_all_examples_does_not_write_to_stderr_on_failure
    _, err = capture_subprocess_io do
      assert_raises(Minitest::Assertion) do
        assert_all_examples(integers(min_value: 0, max_value: 10)) { |n| n > 10 }
      end
    end

    assert_empty err
  end

  # Same reasoning as the assert_all_examples failure test above: a
  # condition every draw satisfies shrinks deterministically to 0.
  def test_assert_no_examples_fails_when_a_value_satisfies_the_condition
    error = assert_raises(Minitest::Assertion) do
      assert_no_examples(integers(min_value: 0, max_value: 10)) { |n| n >= 0 }
    end

    assert_includes error.message, "unexpected example: 0"
  end

  def test_minimal_shrinks_to_the_smallest_satisfying_value
    result = minimal(integers(min_value: 0, max_value: 1_000_000)) { |n| n > 500 }

    assert_equal 501, result
  end

  def test_minimal_fails_as_a_minitest_assertion_when_nothing_satisfies_the_condition
    assert_raises(Minitest::Assertion) do
      minimal(integers(min_value: 0, max_value: 10)) { |n| n > 1_000 }
    end
  end

  # Regression for the "found" flag: a naive implementation that checks
  # `found.nil?` instead of a separate boolean would misreport this run as
  # having found nothing, because nil is exactly the value every draw here
  # produces and the condition is satisfied by.
  def test_minimal_treats_a_generated_nil_as_found_not_a_miss
    generator = integers.map { nil }

    result = minimal(generator) { |value| value.nil? }

    assert_nil result
  end

  def test_find_any_returns_a_value_satisfying_the_condition
    result = find_any(integers(min_value: 0, max_value: 1_000)) { |n| n.odd? }

    assert result.odd?
  end
end
