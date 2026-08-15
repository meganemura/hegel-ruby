# frozen_string_literal: true

require "test_helper"
require "hegel/draw_name"
require "tmpdir"

class TestDrawName < Minitest::Test
  def teardown
    Hegel::DrawName.reset_cache
  end

  def test_returns_the_local_variable_a_single_line_assignment_names
    with_fixture("n = 1\n") do |path|
      assert_equal "n", Hegel::DrawName.for(path, 1)
    end
  end

  # InstanceVariableWriteNode#name already includes the leading "@", so the
  # report can print it unchanged.
  def test_returns_the_instance_variable_name_with_its_leading_at_sign
    with_fixture("@n = 1\n") do |path|
      assert_equal "@n", Hegel::DrawName.for(path, 1)
    end
  end

  # The assignment node's own range spans both lines; either line the
  # caller might report -- the start line or the line the call itself sits
  # on -- must resolve to the same name (see #covers? in lib/hegel/draw_name.rb).
  def test_returns_the_name_for_an_assignment_that_spans_two_lines
    with_fixture("n = tc\n  .draw_integer(0, 10)\n") do |path|
      assert_equal "n", Hegel::DrawName.for(path, 1)
      assert_equal "n", Hegel::DrawName.for(path, 2)
    end
  end

  def test_returns_the_name_behind_a_method_chain_on_one_line
    with_fixture("xs = tc.draw_integer(0, 10).to_s\n") do |path|
      assert_equal "xs", Hegel::DrawName.for(path, 1)
    end
  end

  # Two assignments share the queried line: which one names the draw cannot
  # be decided, so this must return nil rather than guess (see docs/adr/0005).
  def test_returns_nil_when_two_assignments_share_the_same_line
    with_fixture("a = 1; b = 2\n") do |path|
      assert_nil Hegel::DrawName.for(path, 1)
    end
  end

  def test_returns_nil_for_a_line_with_no_assignment_at_all
    with_fixture("foo(1, 2)\n") do |path|
      assert_nil Hegel::DrawName.for(path, 1)
    end
  end

  def test_returns_nil_when_prism_cannot_parse_the_file
    with_fixture("def foo(\n") do |path|
      assert_nil Hegel::DrawName.for(path, 1)
    end
  end

  def test_returns_nil_for_a_path_that_cannot_be_read
    Dir.mktmpdir do |dir|
      missing_path = File.join(dir, "missing.rb")
      assert_nil Hegel::DrawName.for(missing_path, 1)
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
      File.write(path, "n = 1\n")

      assert_equal "n", Hegel::DrawName.for(path, 1)

      File.delete(path)
      assert_equal "n", Hegel::DrawName.for(path, 1),
        "a second #for call for the same path must not reread it"

      Hegel::DrawName.reset_cache
      assert_nil Hegel::DrawName.for(path, 1)
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
end
