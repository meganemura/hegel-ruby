# frozen_string_literal: true

require "test_helper"
require "hegel/draw_name"
require "hegel/test_case"
require "tmpdir"

class TestDrawName < Minitest::Test
  def teardown
    Hegel::DrawName.reset_cache
  end

  def test_returns_the_local_variable_a_single_line_assignment_names
    with_fixture("n = tc.draw(integers)\n") do |path|
      assert_equal "n", draw_name_for(path, 1)
    end
  end

  # InstanceVariableWriteNode#name already includes the leading "@", so the
  # report can print it unchanged.
  def test_returns_the_instance_variable_name_with_its_leading_at_sign
    with_fixture("@n = tc.draw(integers)\n") do |path|
      assert_equal "@n", draw_name_for(path, 1)
    end
  end

  # The assignment node's own range spans both lines; either line the
  # caller might report -- the start line or the line the call itself sits
  # on -- must resolve to the same name (see #covers? in lib/hegel/draw_name.rb).
  def test_returns_the_name_for_an_assignment_that_spans_two_lines
    with_fixture("n = tc\n  .draw_integer(0, 10)\n") do |path|
      assert_equal "n", draw_name_for(path, 1)
      assert_equal "n", draw_name_for(path, 2)
    end
  end

  # The assignment's value node is the .to_s call, not the draw underneath
  # it: the drawn value is an Integer, but xs ends up holding a String, so
  # a name recovered here would describe that String, not the value the
  # report actually prints next to it. ADR 0005's Consequences section
  # lists a method chain as a case the original design had not checked;
  # this is the answer -- nil, the same as any other assignment whose value
  # is merely built from a draw rather than being one.
  def test_returns_nil_for_a_method_chain_where_the_draw_is_the_receiver_not_the_value
    with_fixture("xs = tc.draw_integer(0, 10).to_s\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  # Two assignments share the queried line: which one names the draw cannot
  # be decided, so this must return nil rather than guess (see docs/adr/0005).
  def test_returns_nil_when_two_assignments_share_the_same_line
    with_fixture("a = 1; b = 2\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  def test_returns_nil_for_a_line_with_no_assignment_at_all
    with_fixture("foo(1, 2)\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  def test_returns_nil_when_prism_cannot_parse_the_file
    with_fixture("def foo(\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  def test_returns_nil_for_a_path_that_cannot_be_read
    Dir.mktmpdir do |dir|
      missing_path = File.join(dir, "missing.rb")
      assert_nil draw_name_for(missing_path, 1)
    end
  end

  # The assignment's value node is Date.new(...), whose first argument
  # happens to be a draw call. A name recovered here would say "a date"
  # for a value that is really a year (see docs/adr/0014).
  def test_returns_nil_for_a_draw_nested_inside_another_calls_argument
    with_fixture("d = Date.new(tc.draw_integer(1904, 1904), 2, 29)\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  # Same shape as the Date.new case, with an Array literal built around the
  # draw instead of a method call: the assignment's value node is the
  # ArrayNode, not the draw underneath it.
  def test_returns_nil_for_a_draw_wrapped_in_an_array_literal
    with_fixture("xs = [tc.draw(integers)]\n") do |path|
      assert_nil draw_name_for(path, 1)
    end
  end

  # Proves #for reads a given path at most once: deleting the file between
  # two #for calls for the same path must not change the second call's
  # answer, which it would if the second call re-read (and so failed to
  # read) the now-missing file. #reset_cache is what forces a fresh read
  # afterward: it exists so one test's fixture file cannot answer another
  # test's lookup, and this is where that seam is exercised.
  def test_parses_a_given_path_at_most_once
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fixture.rb")
      File.write(path, "n = tc.draw(integers)\n")

      assert_equal "n", draw_name_for(path, 1)

      File.delete(path)
      assert_equal "n", draw_name_for(path, 1),
        "a second #for call for the same path must not reread it"

      Hegel::DrawName.reset_cache
      assert_nil draw_name_for(path, 1)
    end
  end

  private

  def with_fixture(source)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fixture.rb")
      File.write(path, source)
      yield path
    end
  end

  def draw_name_for(path, lineno)
    Hegel::DrawName.for(path, lineno, Hegel::TestCase::DRAW_METHOD_NAMES)
  end
end
