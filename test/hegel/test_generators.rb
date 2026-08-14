# frozen_string_literal: true

require "test_helper"
require "support/conformance"
require "stringio"

class TestGenerators < Minitest::Test
  include Hegel::Syntax::Methods
  include Hegel::Conformance

  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step regressed (see TestRunner#teardown); every real-engine test in
  # this class must leave none.
  def teardown
    refute Dir.exist?(File.join(Dir.pwd, ".hegel")),
      "a run must not leave a .hegel directory behind"
  end

  # ---- booleans ----

  def test_booleans_draws_against_the_real_engine
    assert_all_examples(booleans) { |v| [true, false].include?(v) }
  end

  # p = 1.0 always yields true without consuming entropy (hegel.h's own
  # documented contract for hegel_generate_boolean), so this is exact, not
  # probabilistic.
  def test_booleans_p_forces_the_probability_of_true
    assert_all_examples(booleans(p: 1.0)) { |v| v == true }
  end

  def test_booleans_p_out_of_range_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(booleans(p: 1.5)) }
    end

    assert_includes error.message, "p must be between"
  end

  # ---- integers ----

  def test_integers_draws_against_the_real_engine
    assert_all_examples(integers) { |v| v.is_a?(Integer) }
  end

  def test_integers_min_value_bounds_the_draw
    assert_all_examples(integers(min_value: 100)) { |v| v >= 100 }
  end

  def test_integers_max_value_bounds_the_draw
    assert_all_examples(integers(max_value: 100)) { |v| v <= 100 }
  end

  def test_integers_min_value_greater_than_max_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(integers(min_value: 5, max_value: 1)) }
    end

    assert_includes error.message, "max_value < min_value"
  end

  def test_integers_bounds_outside_the_64_bit_range_raise_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(integers(max_value: 2**70)) }
    end

    assert_includes error.message, "64-bit range"
  end

  # Constructing a generator with an invalid combination of options must
  # not raise -- only drawing from it does (hegel-rust's own rule; see
  # lib/hegel/generators.rb).
  def test_invalid_generator_options_do_not_raise_until_draw_time
    generator = integers(min_value: 5, max_value: 1)

    assert_kind_of Hegel::Generator, generator
    assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
  end

  # ---- floats ----

  def test_floats_draws_against_the_real_engine
    assert_all_examples(floats) { |v| v.is_a?(Float) }
  end

  def test_floats_min_value_bounds_the_draw
    assert_all_examples(floats(min_value: 0.0)) { |v| v >= 0.0 }
  end

  def test_floats_max_value_bounds_the_draw
    assert_all_examples(floats(max_value: 0.0)) { |v| v <= 0.0 }
  end

  # allow_nan: false (the default) rules NaN out entirely, so this proves
  # the option has an effect rather than merely not raising. No shrink
  # pressure is involved (the property never fails); test_cases: 200 gives
  # the generation phase enough draws to reliably hit NaN even though it is
  # not forced the way p: 1.0 forces a boolean. Neither helper fits: this
  # is an existence check ("some draw is NaN"), which assert_all_examples
  # (a universal check) cannot express, and find_any would add a shrink
  # phase and its own 500-case budget, undermining the "no shrink
  # pressure" and 200-case reasoning above.
  def test_floats_allow_nan_can_draw_nan
    found_nan = false
    Hegel.test(test_cases: 200, verbosity: :quiet) do |tc|
      found_nan ||= tc.draw(floats(allow_nan: true)).nan?
    end

    assert found_nan
  end

  # Same reasoning as allow_nan above, for allow_infinity.
  def test_floats_allow_infinity_can_draw_infinity
    found_infinity = false
    Hegel.test(test_cases: 200, verbosity: :quiet) do |tc|
      found_infinity ||= tc.draw(floats(allow_infinity: true)).infinite?
    end

    assert found_infinity
  end

  def test_floats_exclude_min_excludes_the_minimum
    assert_all_examples(floats(min_value: 0.0, max_value: 1.0, exclude_min: true)) { |v| v > 0.0 }
  end

  def test_floats_exclude_max_excludes_the_maximum
    assert_all_examples(floats(min_value: -1.0, max_value: 0.0, exclude_max: true)) { |v| v < 0.0 }
  end

  def test_floats_min_value_greater_than_max_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(floats(min_value: 5.0, max_value: 1.0)) }
    end

    assert_includes error.message, "max_value < min_value"
  end

  # ---- text ----

  def test_text_draws_against_the_real_engine
    assert_all_examples(text) { |v| v.is_a?(String) }
  end

  def test_text_min_size_bounds_the_draw
    assert_all_examples(text(min_size: 5)) { |v| v.length >= 5 }
  end

  def test_text_max_size_bounds_the_draw
    assert_all_examples(text(max_size: 3)) { |v| v.length <= 3 }
  end

  def test_text_codec_restricts_the_alphabet
    assert_all_examples(text(codec: "ascii")) { |v| v.ascii_only? }
  end

  def test_text_min_codepoint_bounds_the_alphabet
    assert_all_examples(text(min_codepoint: 0x41)) { |v| v.codepoints.all? { |cp| cp >= 0x41 } }
  end

  def test_text_max_codepoint_bounds_the_alphabet
    assert_all_examples(text(max_codepoint: 0x7A)) { |v| v.codepoints.all? { |cp| cp <= 0x7A } }
  end

  def test_text_max_size_less_than_min_size_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(text(min_size: 5, max_size: 1)) }
    end

    assert_includes error.message, "max_size < min_size"
  end

  # ---- arrays ----

  def test_arrays_draws_against_the_real_engine
    assert_all_examples(arrays(integers)) { |v| v.is_a?(Array) }
  end

  def test_arrays_min_size_bounds_the_length
    assert_all_examples(arrays(integers, min_size: 3)) { |v| v.length >= 3 }
  end

  def test_arrays_max_size_bounds_the_length
    assert_all_examples(arrays(integers, max_size: 3)) { |v| v.length <= 3 }
  end

  # arrays(integers): drawn against the real engine, an array's length
  # stays within its bound and every element is an Integer within its own
  # bound.
  def test_arrays_of_integers_have_bounded_length_and_in_range_elements
    assert_all_examples(arrays(integers(min_value: 0, max_value: 10), max_size: 5)) do |v|
      v.length <= 5 && v.all? { |x| x.is_a?(Integer) && x.between?(0, 10) }
    end
  end

  # The canonical shrink-quality regression check for a compound generator
  # (see docs/adr/0006): "no duplicates" falsified by the smallest possible
  # counterexample, two equal elements. This only shrinks to [0, 0] when
  # HEGEL_LABEL_LIST and HEGEL_LABEL_LIST_ELEMENT are placed correctly; a
  # missing or misplaced span still passes this test but shrinks to a
  # larger, non-minimal counterexample instead. Kept as a hand-rolled
  # Hegel.test call, not assert_all_examples: it asserts on the rendered
  # failure report's own output, which this module's helpers deliberately
  # discard (see Hegel::Conformance::DISCARD).
  def test_arrays_composed_with_integers_shrinks_to_the_minimal_duplicate_pair
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        v = tc.draw(arrays(integers(min_value: 0, max_value: 1_000)))
        raise "duplicate in #{v.inspect}" if v.sort != v.sort.uniq
      end
    end

    assert_includes error.message, "[0, 0]"
    assert_includes output.string, "v = [0, 0]"
  end

  def test_arrays_max_size_less_than_min_size_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(arrays(integers, min_size: 5, max_size: 1)) }
    end

    assert_includes error.message, "max_size < min_size"
  end

  def test_arrays_min_size_negative_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(arrays(integers, min_size: -1)) }
    end

    assert_includes error.message, "must not be negative"
  end

  # ---- mixin ----

  # Hegel::Generators.integers (module-level, via Hegel::Generators
  # extending Hegel::Syntax::Methods) and the bare integers this class's
  # own include of Hegel::Syntax::Methods adds (see docs/adr/0004) must
  # build the same generator: with the same seed and derandomize: true,
  # both draw the identical sequence of values.
  def test_generators_module_and_the_bare_mixin_method_return_the_same_generator
    seen_via_module = []
    Hegel.test(seed: 1, derandomize: true, test_cases: 5, verbosity: :quiet) do |tc|
      seen_via_module << tc.draw(Hegel::Generators.integers(min_value: 0, max_value: 100))
    end

    seen_via_mixin = []
    Hegel.test(seed: 1, derandomize: true, test_cases: 5, verbosity: :quiet) do |tc|
      seen_via_mixin << tc.draw(integers(min_value: 0, max_value: 100))
    end

    assert_equal seen_via_module, seen_via_mixin
  end
end
