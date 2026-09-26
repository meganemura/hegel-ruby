# frozen_string_literal: true

require "test_helper"
require "hegel/report"

class TestReport < Minitest::Test
  def test_assign_names_leaves_a_single_occurrence_unsuffixed
    assert_equal [[:draw, "n", 501]], Hegel::Report.assign_names([[:draw, "n", 501]])
  end

  def test_assign_names_suffixes_every_repeated_name_in_draw_order
    entries = [[:draw, "draw", 3], [:draw, "draw", 7], [:draw, "x", 1]]

    assert_equal [[:draw, "draw_1", 3], [:draw, "draw_2", 7], [:draw, "x", 1]], Hegel::Report.assign_names(entries)
  end

  def test_assign_names_on_no_draws_returns_an_empty_array
    assert_empty Hegel::Report.assign_names([])
  end

  # A :note carries no name to disambiguate, so it must not be counted
  # against the :draw tally that shares its fallback name, and it must
  # stay exactly where it was recorded relative to the draws around it.
  def test_assign_names_counts_only_draws_when_a_note_is_interleaved
    entries = [[:draw, "draw", 1], [:note, "checkpoint"], [:draw, "draw", 2]]

    assert_equal [[:draw, "draw_1", 1], [:note, "checkpoint"], [:draw, "draw_2", 2]],
      Hegel::Report.assign_names(entries)
  end

  # A :note's own tag and 2-element shape must survive even when its
  # message happens to match a repeated :draw name: the "unless :draw"
  # guard is what skips a :note before the tally is ever read for it, not
  # the tally coming up empty. A :note's message reused as a repeated
  # draw's own name is the one case that tells the two apart -- without
  # the guard, this :note's own count would read the draws' tally (2, so
  # "> 1") and get rebuilt as a third, spurious [:draw, "n_3", nil].
  def test_assign_names_never_renames_a_note_even_when_its_message_repeats_a_draw_name
    entries = [[:draw, "n", 1], [:draw, "n", 2], [:note, "n"]]

    assert_equal [[:draw, "n_1", 1], [:draw, "n_2", 2], [:note, "n"]], Hegel::Report.assign_names(entries)
  end

  def test_render_one_failure_has_no_distinct_failures_heading
    failure = Hegel::Report::Failure.new(test_cases: 8, discarded: 2, entries: [[:draw, "n", 501]], blob: "AXicY2Ig...")

    text = Hegel::Report.render([failure])

    refute_includes text, "distinct failures"
    assert_includes text, "Falsified after 8 test cases (2 discarded):"
    assert_includes text, "  n = 501"
    assert_includes text, "To reproduce this failure, pass the blob below to Hegel.test:"
    assert_includes text, "    reproduce_failure: \"AXicY2Ig...\""
  end

  def test_render_many_failures_gets_a_distinct_failures_heading_with_a_blank_line_before_each_block
    first = Hegel::Report::Failure.new(test_cases: 3, discarded: 0, entries: [[:draw, "a", 1]], blob: "blob-a")
    second = Hegel::Report::Failure.new(test_cases: 5, discarded: 1, entries: [[:draw, "b", 2]], blob: "blob-b")

    text = Hegel::Report.render([first, second])

    assert_includes text, "Property-based test failed with 2 distinct failures.\n\nFalsified after 3 test cases (0 discarded):"
    assert_includes text, "\n\nFalsified after 5 test cases (1 discarded):"
  end

  # Matches the class-level documentation's own example shape: a :note
  # before and after a :draw, same 2-space indent, in call order.
  def test_render_failure_interleaves_notes_and_draws_in_call_order
    failure = Hegel::Report::Failure.new(
      test_cases: 8, discarded: 2,
      entries: [[:note, "starting the queue"], [:draw, "n", 501], [:note, "queue was empty"]],
      blob: "blob"
    )

    text = Hegel::Report.render_failure(failure)

    assert_includes text, "  starting the queue\n  n = 501\n  queue was empty"
  end

  # A failure with no draws at all -- only notes -- must still render.
  def test_render_failure_with_only_notes_and_no_draws
    failure = Hegel::Report::Failure.new(test_cases: 1, discarded: 0, entries: [[:note, "no draws here"]], blob: "blob")

    text = Hegel::Report.render_failure(failure)

    assert_includes text, "  no draws here"
  end

  # A blank line separates the entries from the "To reproduce" footer, the
  # same way a blank line already separates the header from the entries
  # (the array literal #render_failure starts from) -- without it, the
  # last entry and the footer's first line would run together.
  def test_render_failure_has_a_blank_line_before_the_reproduce_footer
    failure = Hegel::Report::Failure.new(test_cases: 1, discarded: 0, entries: [[:draw, "n", 501]], blob: "blob")

    text = Hegel::Report.render_failure(failure)

    assert_includes text, "  n = 501\n\nTo reproduce this failure, pass the blob below to Hegel.test:"
  end
end
