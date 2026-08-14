# frozen_string_literal: true

require "test_helper"

class TestGenerator < Minitest::Test
  include Hegel::Syntax::Methods

  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step regressed (see TestRunner#teardown); every real-engine test in
  # this class must leave none.
  def teardown
    refute Dir.exist?(File.join(Dir.pwd, ".hegel")),
      "a run must not leave a .hegel directory behind"
  end

  def test_do_draw_raises_not_implemented_for_a_generator_that_does_not_override_it
    generator = Hegel::Generator.new

    assert_raises(NotImplementedError) { generator.do_draw(nil) }
  end

  def test_map_transforms_every_drawn_value_against_the_real_engine
    result = Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
      v = tc.draw(integers(min_value: 0, max_value: 100).map { |n| n * 2 })
      raise "not even: #{v}" unless v.even?
    end

    assert_nil result
  end

  def test_filter_only_yields_values_that_satisfy_the_predicate_against_the_real_engine
    result = Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
      v = tc.draw(integers(min_value: 0, max_value: 100).filter(&:even?))
      raise "not even: #{v}" unless v.even?
    end

    assert_nil result
  end

  # A predicate that never holds must not hang the run: libhegel's own
  # health check aborts it (see Hegel::Generator::Filtered), surfaced here
  # as Hegel::Error the same way any other run-level failure is.
  def test_filter_with_an_impossible_predicate_does_not_loop_forever
    assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) do |tc|
        tc.draw(integers.filter { |_| false })
      end
    end
  end
end
