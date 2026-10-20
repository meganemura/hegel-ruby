# frozen_string_literal: true

require "test_helper"
require "support/conformance"
require "support/fake_lib_hegel"
require "date"
require "ipaddr"
require "stringio"
require "timeout"

# Hegel::LibHegel::Fake (test/support/fake_lib_hegel.rb) accepts any
# #start_span / #stop_span call but does not remember it, so it cannot tell
# a test whether a generator opened the right span, or closed it with the
# right +discard+. This subclass adds that memory, local to this file: no
# other test needs a compound generator's exact span sequence.
class SpanRecordingFake < Hegel::LibHegel::Fake
  attr_reader :span_events

  def initialize
    super
    @span_events = []
  end

  def start_span(ctx, tc, label)
    @span_events << [:start, label]
    super
  end

  def stop_span(ctx, tc, discard)
    @span_events << [:stop, discard]
    super
  end
end

class SequenceRecordingFake < SpanRecordingFake
  attr_reader :collection_sizes, :freed_collections, :integer_bounds
  attr_writer :integer_values

  def initialize
    super
    @collection_sizes = []
    @freed_collections = []
    @integer_bounds = []
    @integer_values = []
  end

  def new_collection(ctx, tc, min_size, max_size)
    @collection_sizes << [min_size, max_size]
    super
  end

  def collection_free(ctx, collection)
    @freed_collections << collection
    super
  end

  def generate_integer(ctx, tc, min_value, max_value)
    @integer_bounds << [min_value, max_value]
    value = super
    @integer_values.empty? ? value : @integer_values.shift
  end
end

# The Fake accepts #collection_reject and forgets it; the reason a
# generator gives is only visible through a subclass that remembers it.
class RejectRecordingFake < Hegel::LibHegel::Fake
  attr_reader :rejections

  def initialize
    super
    @rejections = []
  end

  def collection_reject(ctx, tc, collection, why = nil)
    @rejections << why
    super
  end
end

# Which values reach hegel_generate_float is invisible to a real run when
# the bounds hold no subnormal, so the default allow_subnormal derives
# from the bounds is pinned on what the Fake receives.
class FloatRecordingFake < Hegel::LibHegel::Fake
  attr_reader :magnitudes

  def initialize
    super
    @magnitudes = []
  end

  def generate_float(ctx, tc, width, min_value, max_value, allow_nan, allow_infinity, exclude_min, exclude_max,
    smallest_nonzero_magnitude)
    @magnitudes << smallest_nonzero_magnitude
    super
  end
end

class TestGenerators < Minitest::Test
  include HegelDirectoryGuard
  include Hegel::Syntax::Methods
  include Hegel::Conformance

  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step regressed (see TestRunner#teardown); every real-engine test in
  # this class must leave none.
  def teardown
    refute_new_hegel_directory
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

  # min_value == max_value is the boundary the < check must not reject: it
  # names an exact value, not an empty range.
  def test_integers_min_value_equals_max_value_returns_that_value
    assert_all_examples(integers(min_value: 5, max_value: 5)) { |v| v == 5 }
  end

  # A bound outside int64_t's range dispatches to hegel_generate_integer_big
  # instead of hegel_generate_integer (see IntegerGenerator#do_draw); the
  # caller-facing integers() surface stays the same either way, so this
  # asserts the same thing test_integers_draws_against_the_real_engine does,
  # just with bounds that force the big path on both ends.
  def test_integers_bounds_outside_the_64_bit_range_draw_via_the_big_path
    assert_all_examples(integers(min_value: -(2**100), max_value: 2**100)) do |v|
      v.between?(-(2**100), 2**100)
    end
  end

  # Only one bound outside int64_t's range (min_value defaults to a value
  # that fits, max_value does not): the shape that used to raise "bounds
  # outside the 64-bit range are not supported yet" (a validation this
  # milestone removes; see IntegerGenerator#do_draw) must now draw, not
  # raise.
  def test_integers_max_value_outside_the_64_bit_range_draws_via_the_big_path
    assert_all_examples(integers(max_value: 2**70)) { |v| v <= 2**70 }
  end

  # max_value < min_value is caught before either dispatch branch runs, even
  # when min_value alone is already outside int64_t's range.
  def test_integers_min_value_greater_than_max_value_raises_at_draw_time_even_with_a_big_min_value
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(integers(min_value: 2**100)) }
    end

    assert_includes error.message, "max_value < min_value"
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

  # The tests below fix the defaults docs/adr/0015 adopted: NaN when the
  # caller passed neither bound, an infinity when either side is open.
  #
  # The two existence checks ("some draw is NaN") need a shape the helpers
  # do not have. assert_all_examples states a universal, and find_any would
  # add a shrink phase to a property that never fails. test_cases: 200
  # gives the generation phase enough draws to hit a special value that is
  # not forced the way p: 1.0 forces a boolean. Measured against libhegel
  # 0.45.0, an unseeded run of 200 cases drew no NaN in 6 runs of 200, so
  # the NaN check runs seeded: with seed 1 it draws NaN twice.
  def test_floats_unbounded_draws_nan_by_default
    found_nan = false
    Hegel.test(test_cases: 200, verbosity: :quiet, seed: 1, derandomize: true) do |tc|
      found_nan ||= tc.draw(floats).nan?
    end

    assert found_nan
  end

  # Half-bounded rather than unbounded: this is the case that separates
  # allow_infinity's default (either side open) from allow_nan's (both
  # sides open), and it is the weaker draw of the two, because min_value
  # rules out one of the two infinities. It gets 500 cases where the NaN
  # check above gets 200 for that reason.
  def test_floats_half_bounded_draws_infinity_by_default
    found_infinity = false
    Hegel.test(test_cases: 500, verbosity: :quiet) do |tc|
      found_infinity ||= tc.draw(floats(min_value: 0.0)).infinite?
    end

    assert found_infinity
  end

  def test_floats_fully_bounded_draws_neither_nan_nor_infinity_by_default
    assert_no_examples(floats(min_value: -1.0, max_value: 1.0)) { |v| v.nan? || v.infinite? }
  end

  def test_floats_allow_nan_false_rules_nan_out_when_unbounded
    assert_no_examples(floats(allow_nan: false)) { |v| v.nan? }
  end

  def test_floats_allow_infinity_false_rules_infinity_out_when_unbounded
    assert_no_examples(floats(allow_nan: false, allow_infinity: false)) { |v| v.infinite? }
  end

  # hegel-rust's src/generators/numeric.rs and hegel-go's primitives.go
  # each raise on these two combinations. The asserted substrings are the
  # ones those two messages carry.
  def test_floats_allow_nan_with_a_bound_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(floats(allow_nan: true, min_value: 0.0)) }
    end

    assert_includes error.message, "cannot have allow_nan=true with min_value or max_value"
  end

  def test_floats_allow_infinity_with_both_bounds_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(floats(allow_infinity: true, min_value: 0.0, max_value: 1.0)) }
    end

    assert_includes error.message, "cannot have allow_infinity=true with both min_value and max_value"
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

  # min_value == max_value is the boundary the < check must not reject: it
  # names an exact value, not an empty range.
  def test_floats_min_value_equals_max_value_returns_that_value
    assert_all_examples(floats(min_value: 1.0, max_value: 1.0)) { |v| v.between?(1.0, 1.0) }
  end

  def subnormal?(value)
    value != 0.0 && value.abs < Float::MIN
  end

  def test_floats_allow_subnormal_false_never_draws_a_subnormal
    assert_all_examples(floats(allow_nan: false, allow_infinity: false, allow_subnormal: false)) do |v|
      !subnormal?(v)
    end
  end

  def test_floats_draw_a_subnormal_by_default
    assert subnormal?(find_any(floats(allow_nan: false, allow_infinity: false)) { |v| subnormal?(v) })
  end

  def test_floats_allow_subnormal_true_can_draw_a_subnormal
    found = find_any(floats(allow_nan: false, allow_infinity: false, allow_subnormal: true)) { |v| subnormal?(v) }

    assert subnormal?(found)
  end

  # A range whose only normal values are its two ends: the check that
  # allow_subnormal: false leaves something to draw must not count an end
  # as a subnormal.
  def test_floats_allow_subnormal_false_draws_the_smallest_normal_at_either_end
    assert_all_examples(floats(min_value: Float::MIN, max_value: Float::MIN, allow_subnormal: false)) { |v| v == Float::MIN }
    assert_all_examples(floats(min_value: -Float::MIN, max_value: -Float::MIN, allow_subnormal: false)) { |v| v == -Float::MIN }
  end

  def test_floats_allow_subnormal_false_with_zero_at_either_end_of_a_subnormal_range_draws_zero
    assert_all_examples(floats(min_value: 0.0, max_value: 1e-310, allow_subnormal: false)) { |v| v == 0.0 }
    assert_all_examples(floats(min_value: -1e-310, max_value: 0.0, allow_subnormal: false)) { |v| v == 0.0 }
  end

  def test_floats_allow_subnormal_true_accepts_a_bound_just_below_the_smallest_normal
    assert_all_examples(floats(min_value: Float::MIN.prev_float, max_value: 1.0, allow_subnormal: true)) do |v|
      v >= Float::MIN.prev_float
    end
    assert_all_examples(floats(min_value: -1.0, max_value: (-Float::MIN).next_float, allow_subnormal: true)) do |v|
      v <= (-Float::MIN).next_float
    end
  end

  def test_floats_allow_subnormal_true_with_a_min_value_of_the_smallest_normal_or_more_raises_at_draw_time
    [1.0, Float::MIN].each do |min_value|
      error = assert_raises(Hegel::Error) do
        Hegel.test(verbosity: :quiet) { |tc| tc.draw(floats(min_value: min_value, allow_subnormal: true)) }
      end

      assert_equal "floats: InvalidArgument: allow_subnormal=true, but min_value excludes " \
        "all values below the smallest positive normal #{Float::MIN}", error.message
    end
  end

  def test_floats_allow_subnormal_true_with_a_max_value_of_the_negated_smallest_normal_or_less_raises_at_draw_time
    [-1.0, -Float::MIN].each do |max_value|
      error = assert_raises(Hegel::Error) do
        Hegel.test(verbosity: :quiet) { |tc| tc.draw(floats(max_value: max_value, allow_subnormal: true)) }
      end

      assert_equal "floats: InvalidArgument: allow_subnormal=true, but max_value excludes " \
        "all values above the smallest negative normal -#{Float::MIN}", error.message
    end
  end

  def test_floats_allow_subnormal_false_with_a_range_of_only_subnormals_raises_at_draw_time
    [[5e-324, 1e-310], [-1e-310, -5e-324]].each do |min_value, max_value|
      error = assert_raises(Hegel::Error) do
        Hegel.test(verbosity: :quiet) do |tc|
          tc.draw(floats(min_value: min_value, max_value: max_value, allow_subnormal: false))
        end
      end

      assert_equal "floats: InvalidArgument: allow_subnormal=false leaves no 64-bit " \
        "floating-point values in [#{min_value}, #{max_value}]", error.message
    end
  end

  def smallest_nonzero_magnitude_sent_for(generator)
    fake = FloatRecordingFake.new
    generator.do_draw(Hegel::TestCase.new(fake, fake.context_new, Object.new))
    fake.magnitudes.fetch(0)
  end

  def test_floats_allow_subnormal_defaults_to_what_the_bounds_admit
    subnormal = Hegel::LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED
    {
      {} => subnormal,
      {min_value: -1.0, max_value: 1.0} => subnormal,
      {min_value: 0.0, max_value: 0.0} => subnormal,
      {min_value: Float::MIN.prev_float} => subnormal,
      {max_value: (-Float::MIN).next_float} => subnormal,
      {min_value: Float::MIN} => Float::MIN,
      {min_value: 1.0, max_value: 2.0} => Float::MIN,
      {max_value: -Float::MIN} => Float::MIN,
      {max_value: -1.0} => Float::MIN
    }.each do |options, expected|
      assert_equal expected, smallest_nonzero_magnitude_sent_for(floats(**options)), options.inspect
    end
  end

  def test_floats_explicit_allow_subnormal_overrides_the_default
    assert_equal Float::MIN, smallest_nonzero_magnitude_sent_for(floats(allow_subnormal: false))
    assert_equal 5e-324, smallest_nonzero_magnitude_sent_for(floats(min_value: -1.0, allow_subnormal: true))
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

  # ---- text: alphabet options ----

  # The engine's Unicode tables can be newer than Ruby's, so a codepoint
  # Ruby calls unassigned (Cn) may be a letter to the engine.
  def uppercase_or_unassigned?(char)
    char.match?(/\p{Lu}|\p{Cn}/)
  end

  def draw_error(generator)
    assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
  end

  # What Fake#string_generator_text records for a call that leaves every
  # character option at its default, which is what the engine then sees.
  TEXT_HANDLE_DEFAULTS = {
    codec: nil, min_codepoint: 0, max_codepoint: 0xFFFFFFFF, categories: nil, exclude_categories: nil,
    include_characters: "", exclude_characters: ""
  }.freeze

  def draw_against_fake(generator, fake = Hegel::LibHegel::Fake.new)
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)
    generator.do_draw(tc)
    fake
  end

  def test_text_categories_restrict_the_alphabet
    assert_all_examples(text(categories: ["Lu"], max_size: 20)) do |v|
      v.each_char.all? { |c| uppercase_or_unassigned?(c) }
    end
  end

  def test_text_categories_take_precedence_over_exclude_categories
    assert_all_examples(text(categories: ["Lu"], exclude_categories: ["Lu"], min_size: 1, max_size: 5)) do |v|
      !v.empty? && v.each_char.all? { |c| uppercase_or_unassigned?(c) }
    end
  end

  def test_text_exclude_categories_removes_the_named_categories
    assert_all_examples(text(exclude_categories: ["Cc", "Cs"])) { |v| !v.include?("\n") }
  end

  def test_text_include_characters_with_no_categories_draws_only_those
    assert_all_examples(text(categories: [], include_characters: "xyz", max_size: 20)) { |v| v.match?(/\A[xyz]*\z/) }
  end

  def test_text_exclude_characters_are_never_drawn
    Hegel.test(**Hegel::Conformance::QUIET_SETTINGS) do |tc|
      excluded = tc.draw(text(codec: "ascii"))
      value = tc.draw(text(codec: "ascii", exclude_characters: excluded))
      assert value.each_char.none? { |c| excluded.include?(c) }, "drew an excluded character from #{value.inspect}"
    end
  end

  def test_text_never_draws_a_surrogate
    assert_all_examples(text(min_codepoint: 0xD700, max_codepoint: 0xE000)) do |v|
      v.valid_encoding? && v.codepoints.none? { |cp| cp.between?(0xD800, 0xDFFF) }
    end
  end

  def test_text_alphabet_string_restricts_the_alphabet
    Hegel.test(**Hegel::Conformance::QUIET_SETTINGS) do |tc|
      alphabet = tc.draw(text(codec: "ascii", min_size: 1))
      value = tc.draw(text(alphabet: alphabet))
      assert value.each_char.all? { |c| alphabet.include?(c) }, "#{value.inspect} left #{alphabet.inspect}"
    end
  end

  def test_text_alphabet_string_reaches_every_character_of_it
    find_any(text(alphabet: "abc", min_size: 10)) { |v| v.include?("a") && v.include?("b") && v.include?("c") }
  end

  def test_text_single_character_alphabet_draws_only_that_character
    assert_all_examples(text(alphabet: "x", min_size: 1, max_size: 5)) { |v| v.match?(/\Ax{1,5}\z/) }
  end

  def test_text_alphabet_string_shrinks_to_its_first_character
    assert_equal "AAA", minimal(text(alphabet: "FEDCBA", min_size: 3)) { true }
  end

  # An empty alphabet is legal when no character is drawn from it.
  def test_text_empty_alphabet_draws_the_empty_string_when_max_size_is_zero
    assert_all_examples(text(alphabet: "", max_size: 0)) { |v| v == "" }
  end

  def test_text_alphabet_with_a_character_option_raises_at_draw_time
    options = {
      codec: "ascii", min_codepoint: 0, max_codepoint: 127, categories: ["Lu"], exclude_categories: ["Ll"],
      include_characters: "a", exclude_characters: "b"
    }

    options.each do |name, value|
      error = draw_error(text(alphabet: "abc", **{name => value}))

      assert_includes error.message, "Cannot combine .alphabet() with character methods.", "for #{name}"
    end
  end

  def test_text_alphabet_that_is_not_a_string_raises_at_draw_time
    [3, characters].each do |alphabet|
      error = draw_error(text(alphabet: alphabet))

      assert_includes error.message, "text: alphabet must be a String, not a #{alphabet.class}"
    end
  end

  def test_text_unknown_codec_raises_at_draw_time
    error = draw_error(text(codec: "not-a-real-codec"))

    assert_includes error.message, "text: invalid codec: not-a-real-codec"
  end

  def test_text_accepts_every_supported_codec
    %w[ascii latin-1 iso-8859-1 utf-8].each do |codec|
      assert_all_examples(text(codec: codec)) { |v| v.is_a?(String) }
    end
  end

  def test_text_latin_1_codec_bounds_the_codepoints_to_one_byte
    assert_all_examples(text(codec: "latin-1")) { |v| v.codepoints.all? { |cp| cp <= 0xFF } }
  end

  def test_text_categories_naming_a_surrogate_category_raise_at_draw_time
    %w[Cs C].each do |category|
      error = draw_error(text(categories: [category]))

      assert_includes error.message, "\"#{category}\" includes surrogate codepoints"
    end
  end

  def test_text_nonexistent_category_raises_at_draw_time
    error = draw_error(text(exclude_categories: ["foo"]))

    assert_includes error.message, "foo"
  end

  def test_text_min_codepoint_above_max_codepoint_raises_at_draw_time
    error = draw_error(text(min_codepoint: 200, max_codepoint: 100))

    assert_includes error.message, "No valid characters"
  end

  def test_text_include_characters_overlapping_exclude_characters_raise_at_draw_time
    error = draw_error(text(include_characters: "abc", exclude_characters: "cde"))

    assert_includes error.message, "overlap"
  end

  def test_text_passes_its_options_to_a_text_handle_and_frees_it
    fake = draw_against_fake(
      text(
        min_size: 2, max_size: 7, codec: "ascii", min_codepoint: 3, max_codepoint: 90, categories: ["Lu"],
        exclude_categories: ["Ll"], include_characters: "xy", exclude_characters: "z"
      )
    )

    options, handle = fake.string_generator_text_calls.fetch(0)
    assert_equal(
      {min_size: 2, max_size: 7, codec: "ascii", min_codepoint: 3, max_codepoint: 90, categories: ["Lu"],
       exclude_categories: nil, include_characters: "xy", exclude_characters: "z"},
      options
    )
    assert_equal [handle], fake.freed_string_generators
  end

  def test_text_passes_exclude_categories_when_there_are_no_categories
    fake = draw_against_fake(text(exclude_categories: ["Ll"], max_size: 3))

    assert_equal(
      [TEXT_HANDLE_DEFAULTS.merge(min_size: 0, max_size: 3, exclude_categories: ["Ll"])],
      fake.string_generator_text_calls.map(&:first)
    )
  end

  def test_text_without_options_sends_the_unbounded_size_and_no_character_options
    fake = draw_against_fake(text)

    assert_equal(
      [TEXT_HANDLE_DEFAULTS.merge(min_size: 0, max_size: Hegel::LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED)],
      fake.string_generator_text_calls.map(&:first)
    )
  end

  def test_text_alphabet_string_builds_an_empty_category_handle_that_includes_the_string
    fake = draw_against_fake(text(alphabet: "abc", max_size: 4))

    assert_equal(
      [TEXT_HANDLE_DEFAULTS.merge(min_size: 0, max_size: 4, categories: [], include_characters: "abc")],
      fake.string_generator_text_calls.map(&:first)
    )
  end

  def test_text_frees_its_handle_when_the_draw_raises
    fake = Hegel::LibHegel::Fake.new
    fake.generate_string_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { draw_against_fake(text, fake) }
    assert_equal fake.string_generator_text_calls.map(&:last), fake.freed_string_generators
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
  # the array span and the per-element spans are placed correctly; a
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

  # max_size == min_size is the boundary the < check must not reject: it
  # names an exact length, not an empty range.
  def test_arrays_max_size_equals_min_size_returns_that_length
    assert_all_examples(arrays(integers, min_size: 3, max_size: 3)) { |v| v.length == 3 }
  end

  def test_arrays_unique_has_no_duplicates
    assert_all_examples(arrays(integers(min_value: 0, max_value: 20), unique: true)) { |v| v.uniq == v }
  end

  def test_arrays_unique_false_can_hold_duplicates
    assert find_any(arrays(integers(min_value: 0, max_value: 1), min_size: 2)) { |v| v.uniq != v }
  end

  # A generator that drew min_size elements and dropped the repeats would
  # return fewer, and one that appended a repeat would break the
  # uniqueness; three slots over a domain of three values leave one
  # arrangement each way.
  def test_arrays_unique_reaches_min_size_over_a_domain_of_exactly_that_size
    assert_all_examples(arrays(sampled_from([0, 1, 2]), min_size: 3, max_size: 3, unique: true)) { |v| v.sort == [0, 1, 2] }
  end

  def test_arrays_unique_with_min_size_holds_both_bounds
    assert_all_examples(arrays(integers, min_size: 5, max_size: 8, unique: true)) do |v|
      v.length.between?(5, 8) && v.uniq == v
    end
  end

  def test_arrays_unique_shrinks_to_the_smallest_distinct_values
    assert_equal [0, 1, -1], minimal(arrays(integers, unique: true)) { |v| v.length >= 3 }
  end

  def test_arrays_unique_shrinks_over_sampled_from_to_the_first_values
    assert_equal [0, 1, 2], minimal(arrays(sampled_from((0..9).to_a), min_size: 3, unique: true)) { |_| true }
  end

  def test_arrays_unique_shrinks_using_negative_values
    result = minimal(arrays(integers(min_value: -10, max_value: 10), max_size: 5, unique: true), test_cases: 1000) do |v|
      v.length >= 5
    end

    assert_equal [-2, -1, 0, 1, 2], result.sort
  end

  def test_arrays_unique_rejects_a_repeated_element_with_the_duplicate_element_reason
    fake = RejectRecordingFake.new
    fake.collection_more_count = 3
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

    assert_equal [0], arrays(integers, unique: true).do_draw(tc)
    assert_equal ["duplicate element", "duplicate element"], fake.rejections
  end

  def test_arrays_without_unique_never_rejects_a_repeated_element
    fake = RejectRecordingFake.new
    fake.collection_more_count = 3
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

    assert_equal [0, 0, 0], arrays(integers).do_draw(tc)
    assert_empty fake.rejections
  end

  def test_arrays_unique_keeps_the_array_span_protocol
    generator = arrays(integers, unique: true)
    assert_equal(
      [[:start, generator.label], [:start, integers.label], [:stop, false], [:stop, false]],
      draw_with_span_recording(generator)
    )
  end

  def test_arrays_unique_of_a_single_value_cannot_reach_a_larger_min_size_and_does_not_hang
    error = Timeout.timeout(5) do
      assert_raises(Hegel::Error) do
        Hegel.test(verbosity: :quiet) { |tc| tc.draw(arrays(just(1), min_size: 5, unique: true)) }
      end
    end

    assert_includes error.message, "FilterTooMuch"
  end

  # ---- just ----

  # just draws nothing, so there is no separate real-engine sanity check
  # distinct from asserting the value itself: both live in one test.
  def test_just_always_returns_the_given_value
    assert_all_examples(just(42)) { |v| v == 42 }
  end

  # ---- sampled_from ----

  def test_sampled_from_draws_against_the_real_engine
    assert_all_examples(sampled_from([1, 2, 3])) { |v| [1, 2, 3].include?(v) }
  end

  # Construction alone must not raise (the generator built here is empty,
  # the invalid case); only the draw below does.
  def test_sampled_from_empty_collection_raises_at_draw_time
    generator = sampled_from([])

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "must not be empty"
  end

  # ---- permutations, subsequences, samples ----

  def subsequence?(sub, source)
    remaining = source.each
    sub.all? { |x| remaining.any? { |y| y == x } }
  end

  def sample?(sample, source)
    pool = source.dup
    sample.all? { |x| (i = pool.index(x)) && pool.delete_at(i) }
  end

  def test_permutations_draws_against_the_real_engine
    assert_all_examples(permutations([1, 2, 3, 4])) { |v| v.sort == [1, 2, 3, 4] }
  end

  def test_subsequences_draws_against_the_real_engine
    assert_all_examples(subsequences([1, 2, 3, 4, 5])) { |v| subsequence?(v, [1, 2, 3, 4, 5]) }
  end

  def test_samples_draws_against_the_real_engine
    assert_all_examples(samples([1, 2, 3])) { |v| v.all? { |x| [1, 2, 3].include?(x) } }
  end

  def test_subsequences_min_size_bounds_the_draw
    assert_all_examples(subsequences([1, 2, 3, 4, 5], min_size: 2)) { |v| v.size >= 2 }
  end

  def test_subsequences_max_size_bounds_the_draw
    assert_all_examples(subsequences([1, 2, 3, 4, 5], max_size: 3)) { |v| v.size <= 3 }
  end

  def test_subsequences_max_size_above_the_element_count_is_capped
    assert_all_examples(subsequences([1, 2, 3], max_size: 10)) { |v| v.size <= 3 }
  end

  def test_samples_min_size_bounds_the_draw
    assert_all_examples(samples([1, 2, 3, 4], min_size: 2)) { |v| v.size >= 2 }
  end

  def test_samples_max_size_bounds_the_draw
    assert_all_examples(samples([1, 2, 3, 4], max_size: 2)) { |v| v.size <= 2 }
  end

  def test_samples_without_replacement_uses_each_element_at_most_once
    assert_all_examples(samples([1, 2, 3, 4], replacement: false)) { |v| sample?(v, [1, 2, 3, 4]) }
  end

  def test_samples_without_replacement_caps_the_size_at_the_element_count
    assert_all_examples(samples([1, 2, 3], replacement: false, max_size: 10)) { |v| v.size <= 3 }
  end

  def test_samples_without_replacement_treats_duplicates_as_distinct
    assert_all_examples(samples([1, 1, 2], replacement: false, min_size: 3)) { |v| v.sort == [1, 1, 2] }
  end

  def test_samples_of_an_empty_sequence_are_empty
    assert_all_examples(samples([])) { |v| v.empty? }
    assert_all_examples(samples([], replacement: false)) { |v| v.empty? }
    assert_all_examples(permutations([])) { |v| v.empty? }
    assert_all_examples(subsequences([])) { |v| v.empty? }
  end

  def test_sequence_generators_accept_what_sampled_from_accepts
    assert_all_examples(permutations(1..3)) { |v| v.sort == [1, 2, 3] }
    assert_all_examples(subsequences(Set[1, 2, 3])) { |v| subsequence?(v, [1, 2, 3]) }
    assert_all_examples(samples({a: 1}, min_size: 1, max_size: 1)) { |v| v == [[:a, 1]] }
  end

  def test_permutations_composed_inside_arrays
    assert_all_examples(arrays(permutations([1, 2, 3]), max_size: 5)) { |v| v.all? { |p| p.sort == [1, 2, 3] } }
  end

  def test_samples_composed_inside_arrays
    assert_all_examples(arrays(samples([1, 2, 3], max_size: 3), max_size: 5)) do |v|
      v.all? { |s| s.all? { |x| [1, 2, 3].include?(x) } }
    end
  end

  def test_subsequences_composed_inside_arrays
    assert_all_examples(arrays(subsequences([1, 2, 3]), max_size: 5)) { |v| v.all? { |s| subsequence?(s, [1, 2, 3]) } }
  end

  def test_permutations_shrink_to_the_original_order
    assert_equal [3, 1, 2], minimal(permutations([3, 1, 2])) { true }
  end

  def test_permutations_shrink_by_moving_one_element
    assert_equal [5, 1, 2, 3, 4], minimal(permutations([1, 2, 3, 4, 5])) { |v| v[0] == 5 }
  end

  def test_subsequences_shrink_to_empty
    assert_empty minimal(subsequences([1, 2, 3, 4, 5])) { true }
  end

  def test_subsequences_shrink_to_a_prefix
    assert_equal [1, 2, 3], minimal(subsequences([1, 2, 3, 4, 5], min_size: 3)) { true }
  end

  def test_samples_shrink_to_empty
    assert_empty minimal(samples([1, 2, 3], max_size: 5)) { true }
  end

  def test_samples_with_replacement_can_repeat_an_element
    assert_equal [2, 2], minimal(samples([1, 2], max_size: 5)) { |v| v.count(2) >= 2 }
  end

  def test_samples_with_replacement_shrink_to_the_first_element_repeated
    assert_equal [1, 1, 1], minimal(samples([1, 2, 3], min_size: 3, max_size: 5)) { true }
  end

  def test_samples_without_replacement_shrink_to_a_prefix
    assert_equal [1, 2, 3], minimal(samples([1, 2, 3, 4, 5], replacement: false, min_size: 3)) { true }
  end

  def test_permutations_property
    Hegel.test(**QUIET_SETTINGS) do |tc|
      source = tc.draw(arrays(integers(min_value: -50, max_value: 50), max_size: 10))
      assert_equal source.sort, tc.draw(permutations(source)).sort
    end
  end

  def test_subsequences_size_property
    Hegel.test(**QUIET_SETTINGS) do |tc|
      source = tc.draw(arrays(integers(min_value: -50, max_value: 50), max_size: 10))
      min = tc.draw(integers(min_value: 0, max_value: source.size))
      max = tc.draw(integers(min_value: min, max_value: source.size))
      value = tc.draw(subsequences(source, min_size: min, max_size: max))
      assert_includes min..max, value.size
      assert subsequence?(value, source)
    end
  end

  def test_samples_without_replacement_size_property
    Hegel.test(**QUIET_SETTINGS) do |tc|
      source = tc.draw(arrays(integers(min_value: -50, max_value: 50), max_size: 10))
      min = tc.draw(integers(min_value: 0, max_value: source.size))
      max = tc.draw(integers(min_value: min, max_value: source.size))
      value = tc.draw(samples(source, min_size: min, max_size: max, replacement: false))
      assert_includes min..max, value.size
      assert sample?(value, source)
    end
  end

  def test_samples_with_replacement_size_property
    Hegel.test(**QUIET_SETTINGS) do |tc|
      source = tc.draw(arrays(integers(min_value: -50, max_value: 50), min_size: 1, max_size: 10))
      min = tc.draw(integers(min_value: 0, max_value: 20))
      max = tc.draw(integers(min_value: min, max_value: 20))
      value = tc.draw(samples(source, min_size: min, max_size: max))
      assert_includes min..max, value.size
      assert value.all? { |x| source.include?(x) }
    end
  end

  def draw_error(generator)
    assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }.message
  end

  def test_invalid_sequence_generator_options_do_not_raise_until_draw_time
    [
      subsequences([1], min_size: 2, max_size: 1),
      subsequences([1], min_size: 2),
      subsequences([1], min_size: -1),
      samples([1], min_size: 2, max_size: 1),
      samples([], min_size: 1),
      samples([1], min_size: 2, replacement: false),
      samples([1], min_size: -1)
    ].each { |generator| assert_kind_of Hegel::Generator, generator }
  end

  def test_subsequences_max_size_less_than_min_size_raises_at_draw_time
    assert_equal "subsequences: Cannot have max_size < min_size", draw_error(subsequences([1, 2, 3], min_size: 2, max_size: 1))
  end

  def test_subsequences_min_size_larger_than_the_sequence_raises_at_draw_time
    assert_equal "subsequences: Cannot generate a subsequence: min_size 4 is larger than the 3 elements in the sequence",
      draw_error(subsequences([1, 2, 3], min_size: 4))
  end

  def test_subsequences_negative_min_size_raises_at_draw_time
    assert_equal "subsequences: min_size must not be negative", draw_error(subsequences([1, 2, 3], min_size: -1))
  end

  def test_samples_max_size_less_than_min_size_raises_at_draw_time
    assert_equal "samples: Cannot have max_size < min_size", draw_error(samples([1, 2, 3], min_size: 2, max_size: 1))
    assert_equal "samples: Cannot have max_size < min_size",
      draw_error(samples([1, 2, 3], min_size: 2, max_size: 1, replacement: false))
  end

  def test_samples_with_replacement_from_an_empty_sequence_raises_at_draw_time
    assert_equal "samples: Cannot generate a non-empty sample from an empty sequence", draw_error(samples([], min_size: 1))
  end

  def test_samples_without_replacement_min_size_larger_than_the_sequence_raises_at_draw_time
    assert_equal "samples: Cannot generate a sample without replacement: min_size 4 is larger than the 3 elements in the sequence",
      draw_error(samples([1, 2, 3], min_size: 4, replacement: false))
  end

  def test_samples_negative_min_size_raises_at_draw_time
    assert_equal "samples: min_size must not be negative", draw_error(samples([1, 2, 3], min_size: -1))
  end

  # ---- one_of ----

  def test_one_of_draws_against_the_real_engine
    assert_all_examples(one_of(just(1), just(2))) { |v| [1, 2].include?(v) }
  end

  # Construction alone must not raise (zero generators is the invalid
  # case); only the draw below does.
  def test_one_of_no_generators_raises_at_draw_time
    generator = one_of

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "at least one generator is required"
  end

  # ---- optional ----

  def test_optional_draws_against_the_real_engine
    assert_all_examples(optional(just(1))) { |v| v.nil? || v == 1 }
  end

  # optional is the first generator in this binding that can draw nil.
  # #find_any (Hegel::Conformance) tracks whether the block was ever
  # satisfied with a separate any_found flag rather than found.nil?, so a
  # run that finds nil does not read as "nothing found" -- these two tests
  # exercise that against the real optional(), not just the helper's own
  # unit test.
  def test_optional_can_find_a_nil_example
    assert_nil find_any(optional(just(1))) { |v| v.nil? }
  end

  def test_optional_can_find_a_non_nil_example
    assert_equal 1, find_any(optional(just(1))) { |v| !v.nil? }
  end

  # ---- tuples ----

  def test_tuples_draws_against_the_real_engine
    assert_all_examples(tuples(integers, integers)) { |v| v.is_a?(Array) && v.size == 2 }
  end

  # Zero generators is a valid arity, not an error: the result is the
  # empty tuple, which is what a tuple of nothing is.
  def test_tuples_with_no_generators_returns_an_empty_array
    assert_all_examples(tuples) { |v| v == [] }
  end

  # The tuples analogue of test_arrays_composed_with_integers_shrinks_to_
  # the_minimal_duplicate_pair above: this shrinks to the minimal
  # duplicate, [[0, 0], [0, 0]], only when the tuple span is placed
  # around the whole pair draw; a missing or misplaced span still passes
  # this test but shrinks to a larger, non-minimal counterexample instead.
  def test_arrays_composed_with_tuples_shrinks_to_the_minimal_duplicate_pair
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        v = tc.draw(arrays(tuples(integers(min_value: 0, max_value: 1_000), integers(min_value: 0, max_value: 1_000))))
        raise "duplicate in #{v.inspect}" if v.sort != v.sort.uniq
      end
    end

    assert_includes error.message, "[[0, 0], [0, 0]]"
    assert_includes output.string, "v = [[0, 0], [0, 0]]"
  end

  # ---- sets ----

  def test_sets_draws_against_the_real_engine
    assert_all_examples(sets(integers)) { |v| v.is_a?(Set) }
  end

  def test_sets_min_size_bounds_the_size
    assert_all_examples(sets(integers(min_value: 0, max_value: 1_000), min_size: 3)) { |v| v.size >= 3 }
  end

  def test_sets_max_size_bounds_the_size
    assert_all_examples(sets(integers(min_value: 0, max_value: 1_000), max_size: 3)) { |v| v.size <= 3 }
  end

  # A Set cannot hold a duplicate by construction, so asserting uniqueness
  # on the result alone would pass even without #collection_reject (see
  # Hegel::TestCase#collection_reject): a generator that just called
  # `result << value` unconditionally, letting Set itself silently absorb a
  # repeat, would still return a Set with no duplicates -- just a smaller
  # one than min_size promised. Drawing from a domain of exactly 3 values
  # while requiring 3 distinct elements makes at least one duplicate likely
  # on most attempts, so this exercises the #collection_reject branch and
  # catches that undercounting bug: min_size must still hold.
  def test_sets_rejects_duplicates_without_undercounting_min_size
    assert_all_examples(sets(sampled_from([0, 1, 2]), min_size: 3, max_size: 3)) { |v| v.size == 3 }
  end

  def test_sets_max_size_less_than_min_size_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(sets(integers, min_size: 5, max_size: 1)) }
    end

    assert_includes error.message, "max_size < min_size"
  end

  def test_sets_min_size_negative_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(sets(integers, min_size: -1)) }
    end

    assert_includes error.message, "must not be negative"
  end

  # sets(just(1), min_size: 5) asks for 5 distinct values out of a domain
  # of exactly one: every attempt past the first is a duplicate, forever.
  # Measured against libhegel 0.47.1: #collection_reject itself gives up
  # at the fourth consecutive reject on one collection and raises
  # HEGEL_E_ASSUME (Hegel::AssumeFailed), which Hegel::Runner.classify
  # turns into a discarded (INVALID) test case, not a hang -- and because
  # every test case discards the same way, libhegel's own FilterTooMuch
  # health check then ends the whole run as Hegel::Error after 50 body
  # calls. Timeout.timeout is a second, independent
  # guard: if a future change reintroduces an unbounded retry loop instead,
  # this fails with Timeout::Error in 5 seconds rather than hanging the
  # suite.
  def test_sets_of_a_single_value_cannot_reach_a_larger_min_size_and_does_not_hang
    error = Timeout.timeout(5) do
      assert_raises(Hegel::Error) do
        Hegel.test(verbosity: :quiet) { |tc| tc.draw(sets(just(1), min_size: 5)) }
      end
    end

    assert_includes error.message, "FilterTooMuch"
  end

  # The sets analogue of test_arrays_composed_with_integers_shrinks_to_the_
  # minimal_duplicate_pair above, proving the set span and the per-element
  # spans are placed correctly. min_size: 1 forces at least one element
  # draw per set (min_size: 0 would let both sets shrink to empty without
  # ever opening an element span). Set#inspect's own rendering differs
  # across supported Ruby versions, so the assertion converts each set to
  # an Array first rather than depending on it.
  def test_arrays_composed_with_sets_shrinks_to_the_minimal_duplicate_pair
    error = assert_raises(RuntimeError) do
      Hegel.test(verbosity: :quiet) do |tc|
        v = tc.draw(arrays(sets(integers(min_value: 0, max_value: 1_000), min_size: 1, max_size: 1)))
        raise "duplicate in #{v.map(&:to_a).inspect}" if v.uniq != v
      end
    end

    assert_includes error.message, "[[0], [0]]"
  end

  # ---- hashes ----

  def test_hashes_draws_against_the_real_engine
    assert_all_examples(hashes(integers, integers)) { |v| v.is_a?(Hash) }
  end

  def test_hashes_min_size_bounds_the_size
    assert_all_examples(hashes(integers(min_value: 0, max_value: 1_000), integers, min_size: 3)) { |v| v.size >= 3 }
  end

  def test_hashes_max_size_bounds_the_size
    assert_all_examples(hashes(integers(min_value: 0, max_value: 1_000), integers, max_size: 3)) { |v| v.size <= 3 }
  end

  # The hashes analogue of test_sets_rejects_duplicates_without_
  # undercounting_min_size above: a Hash cannot hold a duplicate key by
  # construction either, so this exercises #collection_reject the same
  # way, judged on the key alone.
  def test_hashes_rejects_duplicate_keys_without_undercounting_min_size
    assert_all_examples(hashes(sampled_from([0, 1, 2]), integers, min_size: 3, max_size: 3)) { |v| v.size == 3 }
  end

  def test_hashes_max_size_less_than_min_size_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(hashes(integers, integers, min_size: 5, max_size: 1)) }
    end

    assert_includes error.message, "max_size < min_size"
  end

  def test_hashes_min_size_negative_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(hashes(integers, integers, min_size: -1)) }
    end

    assert_includes error.message, "must not be negative"
  end

  # ---- characters ----

  def test_characters_draws_against_the_real_engine
    assert_all_examples(characters) { |v| v.is_a?(String) && v.length == 1 }
  end

  def test_characters_codec_restricts_the_alphabet
    assert_all_examples(characters(codec: "ascii")) { |v| v.ascii_only? }
  end

  def test_characters_min_codepoint_bounds_the_alphabet
    assert_all_examples(characters(min_codepoint: 0x41)) { |v| v.codepoints.all? { |cp| cp >= 0x41 } }
  end

  def test_characters_max_codepoint_bounds_the_alphabet
    assert_all_examples(characters(max_codepoint: 0x7A)) { |v| v.codepoints.all? { |cp| cp <= 0x7A } }
  end

  def test_characters_categories_restrict_the_alphabet
    assert_all_examples(characters(categories: ["Lu"])) { |v| uppercase_or_unassigned?(v) }
  end

  def test_characters_exclude_categories_with_a_bounded_range
    generator = characters(exclude_categories: ["Lu"], min_codepoint: 0x30, max_codepoint: 0x39)

    assert_all_examples(generator) { |v| v.match?(/\A[0-9]\z/) }
  end

  def test_characters_include_characters_with_no_categories_draws_only_those
    assert_all_examples(characters(categories: [], include_characters: "xyz")) { |v| "xyz".include?(v) }
  end

  def test_characters_exclude_characters_are_never_drawn
    Hegel.test(**Hegel::Conformance::QUIET_SETTINGS) do |tc|
      excluded = tc.draw(text(codec: "ascii"))
      value = tc.draw(characters(codec: "ascii", exclude_characters: excluded))
      assert_equal false, excluded.include?(value), "drew #{value.inspect} from #{excluded.inspect}"
    end
  end

  def test_characters_codepoint_range_holds_for_any_bounds
    Hegel.test(**Hegel::Conformance::QUIET_SETTINGS) do |tc|
      low = tc.draw(integers(min_value: 0, max_value: 0x10FFFF))
      high = tc.draw(integers(min_value: low, max_value: 0x10FFFF))
      tc.assume(low < 0xD800 || high > 0xDFFF)
      codepoint = tc.draw(characters(min_codepoint: low, max_codepoint: high)).ord
      assert codepoint.between?(low, high), "#{codepoint} is outside #{low}..#{high}"
    end
  end

  def test_characters_single_codepoint_range_shrinks_to_that_character
    assert_equal "0", minimal(characters(min_codepoint: 48, max_codepoint: 48)) { true }
  end

  def test_characters_exclude_characters_shrink_past_the_excluded_ones
    generator = characters(min_codepoint: 0x30, max_codepoint: 0x39, exclude_characters: "te02тест49st")

    assert_equal "1", minimal(generator) { true }
  end

  def test_characters_include_characters_override_the_codepoint_range
    generator = characters(min_codepoint: 0x30, max_codepoint: 0x39, include_characters: "teтестst")

    find_any(generator) { |v| "teтестst".include?(v) }
    find_any(generator) { |v| "0123456789".include?(v) }
    assert_no_examples(generator) { |v| !"teтестst0123456789".include?(v) }
  end

  def test_characters_exclude_characters_disjoint_from_include_characters_are_never_drawn
    generator = characters(min_codepoint: 0x30, max_codepoint: 0x39, exclude_characters: "456def",
      include_characters: "123abc")

    assert_no_examples(generator) { |v| "456def".include?(v) }
  end

  def test_characters_large_exclude_characters_are_never_drawn
    identifier_characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"

    assert_all_examples(characters(exclude_characters: identifier_characters)) { |v| !identifier_characters.include?(v) }
  end

  def test_characters_unknown_codec_raises_at_draw_time
    error = draw_error(characters(codec: "not-a-real-codec"))

    assert_includes error.message, "characters: invalid codec: not-a-real-codec"
  end

  def test_characters_accepts_every_supported_codec
    %w[ascii latin-1 iso-8859-1 utf-8].each do |codec|
      assert_all_examples(characters(codec: codec)) { |v| v.length == 1 }
    end
  end

  def test_characters_categories_naming_a_surrogate_category_raise_at_draw_time
    %w[Cs C].each do |category|
      error = draw_error(characters(categories: [category]))

      assert_includes error.message, "characters: Category \"#{category}\" includes surrogate codepoints"
    end
  end

  def test_characters_exclude_categories_naming_a_surrogate_category_are_accepted
    assert_all_examples(characters(exclude_categories: ["Cs"])) { |v| v.valid_encoding? }
  end

  def test_characters_nonexistent_category_raises_at_draw_time
    error = draw_error(characters(exclude_categories: ["foo"]))

    assert_includes error.message, "foo"
  end

  def test_characters_min_codepoint_above_max_codepoint_raises_at_draw_time
    error = draw_error(characters(min_codepoint: 42, max_codepoint: 24))

    assert_includes error.message, "No valid characters"
  end

  def test_characters_excluding_every_available_character_raises_at_draw_time
    error = draw_error(characters(min_codepoint: 0x30, max_codepoint: 0x30, exclude_characters: "0"))

    assert_includes error.message, "No valid characters"
  end

  def test_characters_categories_that_leave_nothing_in_the_range_raise_at_draw_time
    error = draw_error(characters(categories: ["Cc"], min_codepoint: 0x30, max_codepoint: 0x39))

    assert_includes error.message, "No valid characters"
  end

  def test_characters_include_characters_overlapping_exclude_characters_raise_at_draw_time
    error = draw_error(
      characters(min_codepoint: 0x30, max_codepoint: 0x39, include_characters: "te02тест49st",
        exclude_characters: "ts94тсет")
    )

    assert_includes error.message, "overlap"
  end

  def test_characters_passes_its_options_to_a_one_character_handle_and_frees_it
    fake = draw_against_fake(
      characters(
        codec: "ascii", min_codepoint: 3, max_codepoint: 90, categories: ["Lu"], include_characters: "xy",
        exclude_characters: "z"
      )
    )

    options, handle = fake.string_generator_text_calls.fetch(0)
    assert_equal(
      {min_size: 1, max_size: 1, codec: "ascii", min_codepoint: 3, max_codepoint: 90, categories: ["Lu"],
       exclude_categories: nil, include_characters: "xy", exclude_characters: "z"},
      options
    )
    assert_equal [handle], fake.freed_string_generators
  end

  def test_characters_options_given_is_false_without_options_and_true_with_any
    refute characters.options_given?
    assert characters(categories: []).options_given?
  end

  # ---- binary ----

  def test_binary_draws_against_the_real_engine
    assert_all_examples(binary) { |v| v.is_a?(String) && v.encoding == Encoding::BINARY }
  end

  def test_binary_min_size_bounds_the_draw
    assert_all_examples(binary(min_size: 5)) { |v| v.bytesize >= 5 }
  end

  def test_binary_max_size_bounds_the_draw
    assert_all_examples(binary(max_size: 3)) { |v| v.bytesize <= 3 }
  end

  def test_binary_max_size_less_than_min_size_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(binary(min_size: 5, max_size: 1)) }
    end

    assert_includes error.message, "max_size < min_size"
  end

  # max_size == min_size is the boundary the < check must not reject: it
  # names an exact length, not an empty range.
  def test_binary_max_size_equals_min_size_returns_that_length
    assert_all_examples(binary(min_size: 3, max_size: 3)) { |v| v.bytesize == 3 }
  end

  # ---- from_regex ----

  # fullmatch: false (the default): the drawn string only has to contain a
  # match, not equal one, so this checks for the pattern anywhere in the
  # result rather than anchoring it. "[a-z]{3}" is simple enough to mean
  # the same thing in Python re syntax (what the engine draws against) and
  # Ruby's Regexp syntax (what this assertion checks with), so the
  # assertion cannot pass or fail on a difference between the two.
  def test_from_regex_draws_against_the_real_engine
    assert_all_examples(from_regex("[a-z]{3}")) { |v| v.match?(/[a-z]{3}/) }
  end

  # fullmatch: true requires the whole drawn string to match, which this
  # anchors with \A...\z to check on the Ruby side (see Test 5 in the
  # skill: Ruby-side matching, and a pattern simple enough not to change
  # meaning between the two regex syntaxes).
  def test_from_regex_fullmatch_true_matches_the_whole_string
    assert_all_examples(from_regex("[a-z]{3}", fullmatch: true)) { |v| v.match?(/\A[a-z]{3}\z/) }
  end

  # An empty pattern goes to the engine as a zero-length buffer. Since
  # libhegel 0.45.1 the engine reads a NULL pointer with length zero as the
  # empty pattern, and it rejects a NULL pointer with a nonzero length.
  # FFI::MemoryPointer.new(0) is not NULL, so this binding sends neither
  # case, and the empty pattern fully matches only the empty string.
  def test_from_regex_empty_pattern_fullmatch_draws_the_empty_string
    assert_all_examples(from_regex("", fullmatch: true)) { |v| v == "" }
  end

  # Construction alone must not raise (a Regexp is a legal, if useless,
  # argument to build a generator from); only the draw below does.
  def test_from_regex_pattern_must_be_a_string_raises_at_draw_time
    generator = from_regex(/[a-z]{3}/)

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "must be a String"
  end

  # Since libhegel 0.45.7 the engine refuses to build a regex generator for
  # a pattern that no string matches, so the draw raises and names the
  # pattern. Measured against 0.45.4, the same run raised Unsatisfiable
  # instead, which does not point at the pattern.
  def test_from_regex_pattern_that_matches_nothing_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(test_cases: 20, verbosity: :quiet, output: StringIO.new) { |tc| tc.draw(from_regex("(?!)")) }
    end
    assert_includes error.message, "matches no string"
  end

  # ---- from_regex: alphabet ----

  def test_from_regex_alphabet_restricts_every_character
    generator = from_regex("[a-z]+", fullmatch: true, alphabet: characters(max_codepoint: 0x7F))

    assert_all_examples(generator) { |v| v.match?(/\A[a-z]+\z/) }
  end

  # The padding around a partial match comes from the alphabet too.
  def test_from_regex_alphabet_restricts_the_padding_of_a_partial_match
    generator = from_regex("x", fullmatch: false, alphabet: characters(categories: [], include_characters: "xy"))

    assert_all_examples(generator) { |v| v.match?(/\A[xy]*x[xy]*\z/) }
  end

  def test_from_regex_generates_each_pattern_over_a_wide_alphabet
    patterns = [
      ".", "a", "abc", "[a][b][c]", "[^a][^b][^c]", "[a-z0-9_]", "[^a-z0-9_]", "ab?", "ab*", "ab+", "ab{5,10}",
      "ab|cd|ef", "(foo)+", '\d', '\w', '\s'
    ]

    patterns.each do |pattern|
      generator = from_regex(pattern, fullmatch: true, alphabet: characters(max_codepoint: 1000))

      assert_all_examples(generator) { |v| v.codepoints.all? { |cp| cp <= 1000 } }
    end
  end

  def test_from_regex_alphabet_keeps_a_flag_scoped_literal_out_of_the_draw
    generator = from_regex("(?-i:Ā)*k", fullmatch: true, alphabet: characters(max_codepoint: 127))

    assert_all_examples(generator) { |v| v == "k" }
  end

  def test_from_regex_alphabet_that_cannot_match_the_pattern_raises_at_draw_time
    {
      "abc" => characters(min_codepoint: 128),
      "aa|bb" => characters(include_characters: "c", max_codepoint: 0),
      "[abc]" => characters(include_characters: "def", max_codepoint: 0),
      "[ab]x[de]" => characters(min_codepoint: "a".ord, max_codepoint: "f".ord),
      "[a-z]" => characters(codec: "ascii", categories: ["Nd"]),
      '\d' => characters(include_characters: "abc", max_codepoint: 0),
      "[^a]" => characters(min_codepoint: "a".ord, max_codepoint: "a".ord)
    }.each do |pattern, alphabet|
      error = draw_error(from_regex(pattern, alphabet: alphabet))

      assert_includes error.message, "matches no string over the alphabet", "for #{pattern}"
    end
  end

  def test_from_regex_alternative_outside_the_alphabet_is_skipped
    generator = from_regex("[^a]|a", fullmatch: true, alphabet: characters(min_codepoint: "a".ord, max_codepoint: "a".ord))

    assert_all_examples(generator) { |v| v == "a" }
  end

  # An alphabet with no characters still builds, because its handle draws
  # strings of length zero; a pattern that needs no character matches.
  def test_from_regex_empty_alphabet_matches_a_pattern_that_needs_no_character
    assert_all_examples(from_regex("", fullmatch: true, alphabet: characters(categories: []))) { |v| v == "" }
  end

  def test_from_regex_alphabet_that_is_not_a_characters_generator_raises_at_draw_time
    error = draw_error(from_regex("a", alphabet: "abc"))

    assert_includes error.message, "from_regex: alphabet must be a characters generator, not a String"
  end

  def test_from_regex_alphabet_with_an_unknown_codec_raises_at_draw_time
    error = draw_error(from_regex("a", alphabet: characters(codec: "not-a-real-codec")))

    assert_includes error.message, "from_regex: invalid codec: not-a-real-codec"
  end

  def test_from_regex_alphabet_builds_a_zero_length_text_handle_and_frees_both_handles
    fake = draw_against_fake(from_regex("a+", fullmatch: true, alphabet: characters(max_codepoint: 90)))

    (text_options, alphabet_handle) = fake.string_generator_text_calls.fetch(0)
    (regex_arguments, regex_handle) = fake.string_generator_regex_calls.fetch(0)
    assert_equal TEXT_HANDLE_DEFAULTS.merge(min_size: 0, max_size: 0, max_codepoint: 90), text_options
    assert_equal({pattern: "a+", fullmatch: true, alphabet: alphabet_handle}, regex_arguments)
    assert_equal [regex_handle, alphabet_handle], fake.freed_string_generators
  end

  def test_from_regex_without_an_alphabet_builds_no_text_handle
    fake = draw_against_fake(from_regex("a+"))

    assert_empty fake.string_generator_text_calls
    assert_equal [{pattern: "a+", fullmatch: false, alphabet: nil}], fake.string_generator_regex_calls.map(&:first)
  end

  def test_from_regex_frees_the_alphabet_handle_when_building_the_regex_handle_raises
    fake = Hegel::LibHegel::Fake.new
    fake.string_generator_regex_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { draw_against_fake(from_regex("a", alphabet: characters), fake) }
    assert_equal fake.string_generator_text_calls.map(&:last), fake.freed_string_generators
  end

  # ---- emails ----

  def test_emails_draws_against_the_real_engine
    assert_all_examples(emails) { |v| v.is_a?(String) }
  end

  # ---- urls ----

  def test_urls_draws_against_the_real_engine
    assert_all_examples(urls) { |v| v.is_a?(String) }
  end

  # ---- domains ----

  def test_domains_draws_against_the_real_engine
    assert_all_examples(domains) { |v| v.is_a?(String) }
  end

  def test_domains_max_length_bounds_the_draw
    assert_all_examples(domains(max_length: 20)) { |v| v.length <= 20 }
  end

  # This layer does not validate max_length itself:
  # hegel_string_generator_domain rejects a value outside its documented
  # 4..=255 range, and LibHegel.check! translates that
  # HEGEL_E_INVALID_ARG into this Hegel::Error. Checking it here as well
  # would mean two messages for one mistake, free to drift apart.
  def test_domains_max_length_out_of_range_raises_at_draw_time
    generator = domains(max_length: 3)

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "HEGEL_E_INVALID_ARG"
  end

  # ---- ip_addresses ----

  def test_ip_addresses_draws_against_the_real_engine
    assert_all_examples(ip_addresses) { |v| v.is_a?(IPAddr) }
  end

  def test_ip_addresses_v4_only_draws_ipv4_addresses
    assert_all_examples(ip_addresses(v6: false)) { |v| v.ipv4? }
  end

  def test_ip_addresses_v6_only_draws_ipv6_addresses
    assert_all_examples(ip_addresses(v4: false)) { |v| v.ipv6? }
  end

  # With both families enabled (the default), the family choice itself
  # varies from draw to draw -- these two find an example of each, the
  # same way test_optional_can_find_a_nil_example / _a_non_nil_example
  # prove optional's own boolean choice goes both ways.
  def test_ip_addresses_v4_and_v6_can_find_an_ipv4_example
    assert find_any(ip_addresses) { |v| v.ipv4? }.ipv4?
  end

  def test_ip_addresses_v4_and_v6_can_find_an_ipv6_example
    assert find_any(ip_addresses) { |v| v.ipv6? }.ipv6?
  end

  # Construction alone must not raise; only the draw below does.
  def test_ip_addresses_v4_and_v6_both_false_raises_at_draw_time
    generator = ip_addresses(v4: false, v6: false)

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "must not both be false"
  end

  # ---- uuids ----

  def test_uuids_draws_against_the_real_engine
    assert_all_examples(uuids) { |v| v.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/) }
  end

  # version: 4 forces the version nibble, the first character of the third
  # group -- index 14 in the formatted String (0-based; see
  # UuidsGenerator#do_draw).
  def test_uuids_version_forces_the_version_nibble
    assert_all_examples(uuids(version: 4)) { |v| v[14] == "4" }
  end

  # This layer does not validate version itself: hegel_generate_uuid
  # rejects a value outside its documented 0..15 range, and
  # LibHegel.check! translates that HEGEL_E_INVALID_ARG into this
  # Hegel::Error, the same division of labor #domains follows for its own
  # out-of-range max_length.
  def test_uuids_version_out_of_range_raises_at_draw_time
    generator = uuids(version: 16)

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "HEGEL_E_INVALID_ARG"
  end

  # ---- dates ----

  def test_dates_draws_against_the_real_engine
    assert_all_examples(dates) { |v| v.is_a?(Date) }
  end

  def test_dates_min_value_bounds_the_draw
    bound = Date.new(2020, 1, 1)
    assert_all_examples(dates(min_value: bound)) { |v| v >= bound }
  end

  def test_dates_max_value_bounds_the_draw
    bound = Date.new(2020, 12, 31)
    assert_all_examples(dates(max_value: bound)) { |v| v <= bound }
  end

  def test_dates_min_value_greater_than_max_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(dates(min_value: Date.new(2020, 1, 2), max_value: Date.new(2020, 1, 1))) }
    end

    assert_includes error.message, "max_value < min_value"
  end

  # min_value == max_value pins LibHegel::Real#pack_date/#unpack_date's own
  # byte convention against the engine's own interpretation, not just this
  # binding's encode/decode as each other's inverse (see the skill's own
  # note on why a round trip alone cannot catch a self-consistent but wrong
  # byte convention). Both ends of the conventional full range: year 1
  # month 1 day 1, and year 9999 month 12 day 31 -- the latter alone
  # already has three distinct field values, so it also catches a
  # month/day swap (a swap would try month 31, an invalid month, and raise
  # instead of returning the expected Date).
  def test_dates_min_value_equals_max_value_returns_that_date
    [Date.new(1, 1, 1), Date.new(9999, 12, 31)].each do |date|
      value = nil
      Hegel.test(test_cases: 1, verbosity: :quiet) { |tc| value = tc.draw(dates(min_value: date, max_value: date)) }
      assert_equal date, value
    end
  end

  # ---- times ----

  def test_times_draws_against_the_real_engine
    assert_all_examples(times) { |v| v.is_a?(String) && v.match?(/\A\d{2}:\d{2}:\d{2}\.\d{6}\z/) }
  end

  def test_times_min_value_bounds_the_draw
    assert_all_examples(times(min_value: "12:00:00.000000")) { |v| v >= "12:00:00.000000" }
  end

  def test_times_max_value_bounds_the_draw
    assert_all_examples(times(max_value: "12:00:00.000000")) { |v| v <= "12:00:00.000000" }
  end

  def test_times_min_value_greater_than_max_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(times(min_value: "12:00:00.000001", max_value: "12:00:00.000000")) }
    end

    assert_includes error.message, "max_value < min_value"
  end

  # A min_value/max_value that is not a String matching "HH:MM:SS.ffffff"
  # raises at draw time, not at construction: 123 (not a String at all)
  # and "1:2:3.4" (a String, but the wrong shape) exercise the two
  # branches TimesGenerator#parse's own `value.is_a?(String) &&
  # FORMAT.match(value)` check has.
  def test_times_min_value_not_a_valid_time_string_raises_at_draw_time
    [123, "1:2:3.4"].each do |bad|
      generator = times(min_value: bad)

      assert_kind_of Hegel::Generator, generator
      error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
      assert_includes error.message, "must be \"HH:MM:SS.ffffff\""
    end
  end

  # min_value == max_value pins LibHegel::Real#pack_time/#unpack_time's own
  # byte convention against the engine's own interpretation. The boundary
  # values (00:00:00.000000, 23:59:59.999999) are swap-symmetric in
  # minute/second (00 vs 00, 59 vs 59), so a minute<->second packing bug
  # would still pass them; 13:45:06.123456, where every field is distinct,
  # is what catches that.
  def test_times_min_value_equals_max_value_returns_that_time
    ["00:00:00.000000", "23:59:59.999999", "13:45:06.123456"].each do |time|
      value = nil
      Hegel.test(test_cases: 1, verbosity: :quiet) { |tc| value = tc.draw(times(min_value: time, max_value: time)) }
      assert_equal time, value
    end
  end

  # ---- datetimes ----

  def test_datetimes_draws_against_the_real_engine
    assert_all_examples(datetimes) { |v| v.is_a?(Time) }
  end

  def test_datetimes_min_value_bounds_the_draw
    bound = Time.utc(2020, 1, 1)
    assert_all_examples(datetimes(min_value: bound)) { |v| v >= bound }
  end

  def test_datetimes_max_value_bounds_the_draw
    bound = Time.utc(2020, 12, 31, 23, 59, 59, 999_999)
    assert_all_examples(datetimes(max_value: bound)) { |v| v <= bound }
  end

  # A bound with a fraction of a microsecond: every drawn value, which has
  # whole microseconds, still lies inside it.
  def test_datetimes_bounds_with_a_fraction_of_a_microsecond_bound_the_draw
    min_value = Time.utc(2020, 1, 1, 0, 0, 0, Rational(3, 2))
    max_value = Time.utc(2020, 1, 1, 0, 0, 0, Rational(11, 2))
    assert_all_examples(datetimes(min_value: min_value, max_value: max_value)) do |v|
      v.between?(min_value, max_value)
    end
  end

  def test_datetimes_min_value_greater_than_max_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) do |tc|
        tc.draw(datetimes(min_value: Time.utc(2020, 1, 2), max_value: Time.utc(2020, 1, 1)))
      end
    end

    assert_includes error.message, "max_value < min_value"
  end

  # min_value == max_value pins LibHegel::Real#generate_datetime's own
  # struct packing (hegel_date_t followed by hegel_time_t) against the
  # engine's own interpretation. Both ends of the conventional full range,
  # plus one value where every date and time field is distinct
  # (2024-03-17T13:45:06.123456), the same reasoning
  # test_dates_min_value_equals_max_value_returns_that_date and
  # test_times_min_value_equals_max_value_returns_that_time give for their
  # own boundary-only blind spots.
  def test_datetimes_min_value_equals_max_value_returns_that_datetime
    [
      Time.utc(1, 1, 1, 0, 0, 0, 0),
      Time.utc(9999, 12, 31, 23, 59, 59, 999_999),
      Time.utc(2024, 3, 17, 13, 45, 6, 123_456)
    ].each do |datetime|
      value = nil
      Hegel.test(test_cases: 1, verbosity: :quiet) do |tc|
        value = tc.draw(datetimes(min_value: datetime, max_value: datetime))
      end
      assert_equal datetime, value
    end
  end

  # ---- date_strings, time_strings, datetime_strings ----

  DATE_STRING = /\A\d{4}-\d{2}-\d{2}\z/
  TIME_STRING = /\A\d{2}:\d{2}:\d{2}(\.\d{9})?\z/
  DATETIME_STRING = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{9})?\z/

  def parse_date_string(string)
    string.split("-").map(&:to_i)
  end

  def parse_time_string(string)
    clock, fraction = string.split(".")
    hour, minute, second = clock.split(":").map(&:to_i)
    [hour, minute, second, fraction.to_i]
  end

  def parse_datetime_string(string)
    date, time = string.split("T")
    parse_date_string(date) + parse_time_string(time)
  end

  def test_date_strings_draws_against_the_real_engine
    assert_all_examples(date_strings) { |v| v.match?(DATE_STRING) && Date.valid_date?(*parse_date_string(v)) }
  end

  def test_time_strings_draws_against_the_real_engine
    assert_all_examples(time_strings) { |v| v.match?(TIME_STRING) }
  end

  def test_datetime_strings_draws_against_the_real_engine
    assert_all_examples(datetime_strings) { |v| v.match?(DATETIME_STRING) }
  end

  def test_time_strings_reach_nanosecond_precision
    value = find_any(time_strings) { |v| v.include?(".") && !v.end_with?("000") }
    assert_match(/\.\d{9}\z/, value)
  end

  def test_time_strings_reach_a_whole_second
    assert_match(/\A\d{2}:\d{2}:\d{2}\z/, find_any(time_strings) { |v| !v.include?(".") })
  end

  def test_datetime_strings_shrink_to_the_millennium
    assert_equal "2000-01-01T00:00:00", minimal(datetime_strings) { true }
  end

  def test_datetime_strings_are_naive
    assert_all_examples(datetime_strings) { |v| !v.include?("+") && !v.include?("Z") }
  end

  def test_date_strings_shrink_to_the_first_year_after_2000
    assert_equal 2001, parse_date_string(minimal(date_strings) { |v| parse_date_string(v)[0] > 2000 })[0]
  end

  def test_date_strings_shrink_to_the_last_year_before_2000
    assert_equal 1999, parse_date_string(minimal(date_strings) { |v| parse_date_string(v)[0] < 2000 })[0]
  end

  def test_date_strings_reach_every_month
    (1..12).each do |month|
      find_any(date_strings) { |v| parse_date_string(v)[1] == month }
    end
  end

  def test_time_strings_reach_midnight
    find_any(time_strings) { |v| parse_time_string(v)[0, 3] == [0, 0, 0] }
  end

  def test_time_strings_shrink_to_the_first_hour_after_midnight
    assert_equal 1, parse_time_string(minimal(time_strings) { |v| parse_time_string(v)[0] != 0 })[0]
  end

  def test_time_strings_reach_and_miss_the_minute
    find_any(time_strings) { |v| parse_time_string(v)[2].zero? }
    find_any(time_strings) { |v| !parse_time_string(v)[2].zero? }
  end

  def test_time_strings_shrink_to_midnight
    assert_equal "00:00:00", minimal(time_strings) { true }
  end

  def test_time_strings_are_naive
    assert_all_examples(time_strings) { |v| !v.include?("+") && !v.include?("Z") }
  end

  def test_datetime_strings_compose_inside_arrays
    assert_equal ["2000-01-01T00:00:00"] * 2, minimal(arrays(datetime_strings, min_size: 2, max_size: 2)) { true }
  end

  class ArgumentRecordingFake < Hegel::LibHegel::Fake
    attr_reader :calls

    def initialize
      super
      @calls = []
    end

    def generate_date(ctx, tc, min_value, max_value)
      @calls << [:date, min_value, max_value]
      super
    end

    def generate_time(ctx, tc, min_value, max_value)
      @calls << [:time, min_value, max_value]
      super
    end

    def generate_datetime(ctx, tc, min_date, min_time, max_date, max_time)
      @calls << [:datetime, min_date, min_time, max_date, max_time]
      super
    end
  end

  def draw_recording_arguments(generator, **values)
    fake = ArgumentRecordingFake.new
    values.each { |name, value| fake.public_send(:"#{name}=", value) }
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)
    [generator.do_draw(tc), fake.calls]
  end

  def test_date_strings_pad_every_field_and_ask_for_years_1_through_9999
    value, calls = draw_recording_arguments(date_strings, generate_date_value: [1, 2, 3])

    assert_equal "0001-02-03", value
    assert_equal [[:date, [1, 1, 1], [9999, 12, 31]]], calls
  end

  def test_date_strings_keep_a_four_digit_year
    value, = draw_recording_arguments(date_strings, generate_date_value: [9999, 12, 31])

    assert_equal "9999-12-31", value
  end

  def test_time_strings_omit_the_fraction_for_a_whole_second
    value, calls = draw_recording_arguments(time_strings, generate_time_value: [1, 2, 3, 0])

    assert_equal "01:02:03", value
    assert_equal [[:time, [0, 0, 0, 0], [23, 59, 59, 999_999_999]]], calls
  end

  def test_time_strings_print_nine_digits_for_a_nonzero_nanosecond
    assert_equal "01:02:03.000000007", draw_recording_arguments(time_strings, generate_time_value: [1, 2, 3, 7]).first
    assert_equal "23:59:59.999999999",
      draw_recording_arguments(time_strings, generate_time_value: [23, 59, 59, 999_999_999]).first
    assert_equal "01:02:03.123456000", draw_recording_arguments(time_strings, generate_time_value: [1, 2, 3, 123_456_000]).first
  end

  def test_datetime_strings_join_date_and_time_with_t_over_the_full_range
    value, calls = draw_recording_arguments(
      datetime_strings, generate_datetime_value: [[24, 3, 17], [13, 45, 6, 123_456_789]]
    )

    assert_equal "0024-03-17T13:45:06.123456789", value
    assert_equal [[:datetime, [1, 1, 1], [0, 0, 0, 0], [9999, 12, 31], [23, 59, 59, 999_999_999]]], calls
    assert_equal "0001-01-01T00:00:00",
      draw_recording_arguments(datetime_strings, generate_datetime_value: [[1, 1, 1], [0, 0, 0, 0]]).first
  end

  def test_date_time_strings_open_no_span
    [date_strings, time_strings, datetime_strings].each do |generator|
      assert_empty draw_with_span_recording(generator)
    end
  end

  # ---- durations ----

  def test_durations_default_range_is_unsigned_64_bit_nanoseconds
    assert_all_examples(durations) { |v| v.is_a?(Integer) && v.between?(0, 2**64 - 1) }
  end

  def test_durations_bounds_the_draw
    assert_all_examples(durations(min_value: 5, max_value: 60)) { |v| v.between?(5, 60) }
  end

  # The engine's integer draw above int64_t goes through a different native
  # call than below it, so only a draw that cannot fit in 63 bits shows the
  # unsigned range is reachable.
  def test_durations_draw_above_the_signed_64_bit_range
    assert find_any(durations(min_value: 2**63)) { |v| v >= 2**63 }
  end

  def test_durations_min_value_equals_max_value_returns_that_value
    assert_all_examples(durations(min_value: 2**64 - 1)) { |v| v == 2**64 - 1 }
  end

  def test_durations_max_value_above_the_largest_duration_saturates
    assert_all_examples(durations(min_value: 2**64 - 1, max_value: 2**70)) { |v| v == 2**64 - 1 }
  end

  def test_durations_shrinks_to_min_value
    assert_equal 1_000, minimal(durations(min_value: 1_000)) { |_| true }
  end

  def test_durations_composed_inside_arrays_respect_the_bounds
    assert_all_examples(arrays(durations(max_value: 60), max_size: 5)) { |v| v.all? { |d| d <= 60 } }
  end

  def test_durations_min_value_negative_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(durations(min_value: -1)) }
    end

    assert_equal "durations: min_value must not be negative", error.message
  end

  def test_durations_min_value_above_the_largest_duration_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(durations(min_value: 2**64)) }
    end

    assert_equal "durations: min_value exceeds the largest generatable Duration " \
      "(u64::MAX nanoseconds, about 584 years)", error.message
  end

  def test_durations_max_value_less_than_min_value_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(durations(min_value: 5, max_value: 1)) }
    end

    assert_equal "durations: Cannot have max_value < min_value", error.message
  end

  def test_durations_max_value_negative_raises_at_draw_time
    error = assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) { |tc| tc.draw(durations(max_value: -1)) }
    end

    assert_includes error.message, "max_value < min_value"
  end

  # ---- composite ----

  def test_composite_draws_against_the_real_engine
    generator = composite { |dtc| [dtc.draw(integers(min_value: 0, max_value: 10)), dtc.draw(text)] }

    assert_all_examples(generator) { |v| v.is_a?(Array) && v.size == 2 && v[0].is_a?(Integer) && v[1].is_a?(String) }
  end

  # Covers BlockTestCase#draw_integer/#draw_boolean, the two primitives a
  # composite block reaches the same way Hegel::TestCase#draw_integer/
  # #draw_boolean let ordinary code reach the engine directly, without
  # going through #draw and a Hegel::Generator.
  def test_composite_draw_integer_and_draw_boolean_primitives
    generator = composite { |dtc| [dtc.draw_integer(0, 10), dtc.draw_boolean] }

    assert_all_examples(generator) { |v| v[0].between?(0, 10) && [true, false].include?(v[1]) }
  end

  # The span-placement layer (see the skill's Test 3): a composite value
  # built from two dependent integer draws, composed inside arrays(...),
  # shrinks to the minimal duplicate pair only when the composite span
  # wraps the whole composite draw -- a missing or misplaced span still
  # passes but shrinks to a larger, non-minimal counterexample instead
  # (mirrors test_arrays_composed_with_tuples_shrinks_to_the_minimal_duplicate_pair,
  # since a 2-element composite and a 2-generator tuples() draw the same
  # shape of value).
  def test_arrays_composed_with_composite_shrinks_to_the_minimal_duplicate_pair
    pair = composite do |dtc|
      [dtc.draw(integers(min_value: 0, max_value: 1_000)), dtc.draw(integers(min_value: 0, max_value: 1_000))]
    end

    error = assert_raises(RuntimeError) do
      Hegel.test(verbosity: :quiet) do |tc|
        v = tc.draw(arrays(pair))
        raise "duplicate in #{v.inspect}" if v.sort != v.sort.uniq
      end
    end

    assert_includes error.message, "[[0, 0], [0, 0]]"
  end

  def test_composite_without_a_block_raises_at_draw_time
    generator = composite

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "block is required"
  end

  # An array asks for its elements' label before it draws one, so a
  # blockless composite has to answer that with a label too, and leave the
  # error to its own draw.
  def test_composite_without_a_block_inside_arrays_raises_at_draw_time
    generator = arrays(composite, min_size: 1)

    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "block is required"
  end

  # Pins the decision that a composite block's own tc.draw calls do not
  # each get their own report line: BlockTestCase#draw reaches the inner
  # generator's #do_draw directly, never Hegel::TestCase#draw, so the two
  # integer draws below stay unrecorded and only the composite's own
  # value (bound to v) shows in the rendered failure report.
  def test_composite_block_draws_do_not_record_their_own_report_line
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        v = tc.draw(composite { |dtc|
          [dtc.draw(integers(min_value: 0, max_value: 10)), dtc.draw(integers(min_value: 0, max_value: 10))]
        })
        raise "boom: #{v.inspect}"
      end
    end

    assert_includes error.message, "[0, 0]"
    draw_lines = output.string.lines.select { |line| line.start_with?("  ") && line.include?(" = ") }
    assert_equal ["  v = [0, 0]\n"], draw_lines
  end

  # ---- deferred ----

  def test_deferred_draws_after_set
    generator = deferred
    generator.set(integers(min_value: 0, max_value: 10))

    assert_all_examples(generator) { |v| v.between?(0, 10) }
  end

  def test_deferred_draw_before_set_raises_at_draw_time
    generator = deferred

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "draw called before set"
  end

  def test_deferred_set_called_twice_raises
    generator = deferred
    generator.set(integers)

    error = assert_raises(Hegel::Error) { generator.set(integers) }
    assert_includes error.message, "set called more than once"
  end

  # A self-referential generator (the shape a recursive data type like a
  # tree needs) must terminate: the engine's own size control (the
  # collection_more budget arrays() draws against) bounds how many times
  # arrays(tree) recurses into another tree before it stops offering more
  # elements. Timeout.timeout is a second, independent guard, the same
  # role it plays in test_sets_of_a_single_value_cannot_reach_a_larger_
  # min_size_and_does_not_hang above: if a future change reintroduces
  # unbounded recursion, this fails with Timeout::Error rather than
  # hanging the suite.
  def test_deferred_self_referential_generator_terminates
    tree = deferred
    tree.set(one_of(integers, arrays(tree)))

    Timeout.timeout(20) do
      assert_all_examples(tree) { |v| v.is_a?(Integer) || v.is_a?(Array) }
    end
  end

  # ---- span protocol ----
  #
  # A compound generator's own start_span/stop_span calls (see
  # docs/adr/0006): missing one, or closing it with the wrong +discard+,
  # costs nothing the real engine reports back and shows up only as a
  # worse shrunk counterexample -- not something a test against the real
  # engine can pin down directly. Driving #do_draw against
  # SpanRecordingFake instead asserts the exact sequence libhegel itself
  # would see: a missing span drops an entry from the list, and a
  # discard: true where false belongs tells libhegel a successful draw
  # was rejected and should be retried, which is not what happened.

  # Draws +generator+ once against a SpanRecordingFake and returns the
  # span events it recorded. generate_boolean_value: true and
  # collection_more_count: 1 make every conditional draw (optional's
  # coin flip, ip_addresses' family choice, one collection element) take
  # the branch that exercises a compound generator's own span, not the
  # cheaper path around it.
  def draw_with_span_recording(generator)
    fake = SpanRecordingFake.new
    fake.generate_boolean_value = true
    fake.collection_more_count = 1
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)
    generator.do_draw(tc)
    fake.span_events
  end

  def test_arrays_do_draw_opens_its_own_span_and_one_per_element_and_closes_both_kept
    generator = arrays(integers)
    assert_equal(
      [[:start, generator.label], [:start, integers.label], [:stop, false], [:stop, false]],
      draw_with_span_recording(generator)
    )
  end

  def test_sets_do_draw_opens_its_own_span_and_one_per_element_and_closes_both_kept
    generator = sets(integers)
    assert_equal(
      [[:start, generator.label], [:start, integers.label], [:stop, false], [:stop, false]],
      draw_with_span_recording(generator)
    )
  end

  def test_hashes_do_draw_opens_its_own_span_and_one_per_entry_and_closes_both_kept
    generator = hashes(integers, booleans)
    events = draw_with_span_recording(generator)

    assert_equal [:start, generator.label], events[0]
    assert_equal [[:stop, false], [:stop, false]], events[2..]
    refute_includes [generator.label, integers.label, booleans.label], events[1][1]
    refute_equal draw_with_span_recording(hashes(integers, integers))[1][1], events[1][1]
  end

  def test_tuples_do_draw_opens_and_closes_its_own_span_kept
    generator = tuples(integers, integers)
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  def test_optional_do_draw_opens_and_closes_its_own_span_kept
    generator = optional(integers)
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  def test_sampled_from_do_draw_opens_and_closes_its_own_span_kept
    generator = sampled_from([1, 2, 3])
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  def test_one_of_do_draw_opens_and_closes_its_own_span_kept
    generator = one_of(integers)
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  def test_ip_addresses_do_draw_opens_and_closes_its_own_span_kept
    generator = ip_addresses(v6: false)
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  def test_composite_do_draw_opens_and_closes_its_own_span_kept
    generator = composite { |dtc| dtc.draw(integers) }
    assert_equal [[:start, generator.label], [:stop, false]], draw_with_span_recording(generator)
  end

  # ---- sequence generators against the Fake ----

  # Draws +generator+ once against a SequenceRecordingFake. +integers+ are
  # the values generate_integer hands back in turn, +more+ the number of
  # elements the collection offers. Returns the value and the fake.
  def draw_sequence(generator, more: 0, integers: [])
    fake = SequenceRecordingFake.new
    fake.collection_more_count = more
    fake.integer_values = integers
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)
    [generator.do_draw(tc), fake]
  end

  def test_sequence_generators_open_one_span_around_the_whole_draw
    [permutations([1, 2]), subsequences([1, 2]), samples([1, 2]), samples([1, 2], replacement: false)].each do |generator|
      _, fake = draw_sequence(generator, more: 2)
      assert_equal [[:start, generator.label], [:stop, false]], fake.span_events
    end
  end

  def test_sequence_generators_have_distinct_labels
    labels = [permutations([1]), subsequences([1]), samples([1])].map(&:label)
    assert_equal labels.uniq, labels
  end

  def test_sequence_generators_close_the_span_and_free_the_collection_when_a_draw_raises
    [permutations([1, 2]), subsequences([1, 2]), samples([1, 2]), samples([1, 2], replacement: false)].each do |generator|
      fake = SequenceRecordingFake.new
      fake.collection_more_count = 2
      fake.generate_integer_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
      tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

      assert_raises(Hegel::Error) { generator.do_draw(tc) }
      assert_equal [[:start, generator.label], [:stop, false]], fake.span_events
      assert_equal 1, fake.freed_collections.size
    end
  end

  def test_validation_failures_open_no_span_and_no_collection
    [subsequences([1], min_size: 2), samples([], min_size: 1), samples([1], min_size: 2, replacement: false)].each do |generator|
      fake = SequenceRecordingFake.new
      tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

      assert_raises(Hegel::Error) { generator.do_draw(tc) }
      assert_empty fake.span_events
      assert_empty fake.collection_sizes
    end
  end

  def test_permutations_draw_each_index_from_what_is_left
    value, fake = draw_sequence(permutations(%w[a b c]), more: 3, integers: [2, 0, 0])

    assert_equal %w[c a b], value
    assert_equal [[3, 3]], fake.collection_sizes
    assert_equal [[0, 2], [0, 1], [0, 0]], fake.integer_bounds
    assert_equal 1, fake.freed_collections.size
  end

  def test_permutations_of_nothing_draw_no_index
    value, fake = draw_sequence(permutations([]), more: 1)

    assert_empty value
    assert_equal [[0, 0]], fake.collection_sizes
    assert_empty fake.integer_bounds
    assert_equal 1, fake.freed_collections.size
  end

  def test_subsequences_keep_the_original_order
    value, fake = draw_sequence(subsequences(%w[a b c]), more: 2, integers: [2, 0])

    assert_equal %w[a c], value
    assert_equal [[0, 3]], fake.collection_sizes
  end

  def test_subsequences_cap_max_size_at_the_element_count
    assert_equal [[1, 3]], draw_sequence(subsequences([1, 2, 3], min_size: 1, max_size: 10)).last.collection_sizes
    assert_equal [[1, 2]], draw_sequence(subsequences([1, 2, 3], min_size: 1, max_size: 2)).last.collection_sizes
  end

  def test_samples_with_replacement_draw_each_element_from_the_whole_sequence
    value, fake = draw_sequence(samples(%w[a b c]), more: 3, integers: [2, 0, 2])

    assert_equal %w[c a c], value
    assert_equal [[0, Hegel::LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED]], fake.collection_sizes
    assert_equal [[0, 2]] * 3, fake.integer_bounds
    assert_equal 1, fake.freed_collections.size
  end

  def test_samples_with_replacement_pass_max_size_to_the_collection
    assert_equal [[1, 4]], draw_sequence(samples([1, 2], min_size: 1, max_size: 4)).last.collection_sizes
  end

  def test_samples_with_replacement_from_nothing_are_bounded_at_zero
    value, fake = draw_sequence(samples([]))

    assert_empty value
    assert_equal [[0, 0]], fake.collection_sizes
    assert_empty fake.integer_bounds
    assert_equal [[0, 0]], draw_sequence(samples([], max_size: 5)).last.collection_sizes
  end

  def test_samples_without_replacement_cap_max_size_at_the_element_count
    assert_equal [[0, 3]], draw_sequence(samples([1, 2, 3], replacement: false)).last.collection_sizes
    assert_equal [[0, 3]], draw_sequence(samples([1, 2, 3], replacement: false, max_size: 10)).last.collection_sizes
    assert_equal [[0, 2]], draw_sequence(samples([1, 2, 3], replacement: false, max_size: 2)).last.collection_sizes
  end

  def test_samples_without_replacement_keep_draw_order
    value, = draw_sequence(samples(%w[a b c], replacement: false), more: 2, integers: [2, 0])

    assert_equal %w[c a], value
  end

  # ---- labels ----

  # The engine reads two spans with one label as draws of one generator,
  # so a compound generator's label names its components too.
  def test_a_compound_label_names_its_components
    assert_equal arrays(integers).label, arrays(integers, max_size: 3).label
    refute_equal arrays(integers).label, arrays(text).label
    refute_equal arrays(integers).label, sets(integers).label
    refute_equal hashes(integers, text).label, hashes(text, integers).label
    refute_equal one_of(integers, text).label, one_of(text, integers).label
    refute_equal optional(integers).label, optional(text).label
    refute_equal tuples(integers, text).label, tuples(text, integers).label
  end

  # A leaf generator's label depends on its kind, not on its options or on
  # the values it picks from.
  def test_a_leaf_label_names_its_kind
    assert_equal integers.label, integers(min_value: 0, max_value: 9).label
    assert_equal sampled_from([1, 2]).label, sampled_from(%w[a b]).label
    refute_equal integers.label, text.label
  end

  # Two composites written in different places get different labels.
  def test_composites_written_apart_get_different_labels
    first = composite { |dtc| dtc.draw(integers) }
    second = composite { |dtc| dtc.draw(integers) }
    refute_equal first.label, second.label
  end

  # A compound generator keeps its label from when it was built, so drawing
  # it writes nothing to it, and a caller may freeze it.
  def test_a_frozen_compound_generator_draws
    generator = arrays(integers(min_value: 0, max_value: 3).map { |n| n * 2 }).freeze

    Hegel.test(test_cases: 5, verbosity: :quiet) { |tc| tc.draw(generator) }
  end

  # A part that is not a generator fails when the compound generator is
  # drawn, where a generator validates its arguments, so building one around
  # it does not raise.
  def test_a_compound_generator_builds_around_a_part_that_is_not_a_generator
    assert_kind_of Hegel::Generator, arrays(5)
  end

  # A generator built around a deferred one before #set keeps the deferred
  # class's label, so a self-referential definition has no cycle to follow.
  # After #set, the deferred generator answers with the installed one's label.
  def test_a_self_referential_deferred_label_terminates
    tree = deferred
    assert_equal Hegel::Generators::DeferredGenerator.label, tree.label

    inner = one_of(integers, arrays(tree))
    tree.set(inner)

    assert_equal inner.label, tree.label

    assert_equal tree.label, tree.label
    refute_equal Hegel::Generators::DeferredGenerator.label, tree.label
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
