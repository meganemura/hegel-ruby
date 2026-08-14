# frozen_string_literal: true

require "test_helper"
require "hegel/report"

class TestReport < Minitest::Test
  def test_assign_names_leaves_a_single_occurrence_unsuffixed
    assert_equal [["n", 501]], Hegel::Report.assign_names([["n", 501]])
  end

  def test_assign_names_suffixes_every_repeated_name_in_draw_order
    draws = [["draw", 3], ["draw", 7], ["x", 1]]

    assert_equal [["draw_1", 3], ["draw_2", 7], ["x", 1]], Hegel::Report.assign_names(draws)
  end

  def test_assign_names_on_no_draws_returns_an_empty_array
    assert_empty Hegel::Report.assign_names([])
  end

  def test_render_one_failure_has_no_distinct_failures_heading
    failure = Hegel::Report::Failure.new(test_cases: 8, discarded: 2, draws: [["n", 501]], blob: "AXicY2Ig...")

    text = Hegel::Report.render([failure])

    refute_includes text, "distinct failures"
    assert_includes text, "Falsified after 8 test cases (2 discarded):"
    assert_includes text, "  n = 501"
    assert_includes text, "To reproduce this failure, pass the blob below to Hegel.test:"
    assert_includes text, "    reproduce_failure: \"AXicY2Ig...\""
  end

  def test_render_many_failures_gets_a_distinct_failures_heading_with_a_blank_line_before_each_block
    first = Hegel::Report::Failure.new(test_cases: 3, discarded: 0, draws: [["a", 1]], blob: "blob-a")
    second = Hegel::Report::Failure.new(test_cases: 5, discarded: 1, draws: [["b", 2]], blob: "blob-b")

    text = Hegel::Report.render([first, second])

    assert_includes text, "Property-based test failed with 2 distinct failures.\n\nFalsified after 3 test cases (0 discarded):"
    assert_includes text, "\n\nFalsified after 5 test cases (1 discarded):"
  end
end
