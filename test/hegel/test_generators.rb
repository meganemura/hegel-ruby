# frozen_string_literal: true

require "test_helper"
require "support/conformance"
require "stringio"
require "timeout"

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

  # Zero generators is a valid arity, not an error (see the task's own
  # decision record): the result is the empty tuple.
  def test_tuples_with_no_generators_returns_an_empty_array
    assert_all_examples(tuples) { |v| v == [] }
  end

  # The tuples analogue of test_arrays_composed_with_integers_shrinks_to_
  # the_minimal_duplicate_pair above: this shrinks to the minimal
  # duplicate, [[0, 0], [0, 0]], only when HEGEL_LABEL_TUPLE is placed
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
  # Measured against libhegel 0.32.5: #collection_reject itself gives up
  # after a handful of consecutive rejects on one collection and raises
  # HEGEL_E_ASSUME (Hegel::AssumeFailed), which Hegel::Runner.classify
  # turns into a discarded (INVALID) test case, not a hang -- and because
  # every test case discards the same way, libhegel's own FilterTooMuch
  # health check then ends the whole run as Hegel::Error, usually before a
  # second test case even starts. Timeout.timeout is a second, independent
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
  # minimal_duplicate_pair above, proving HEGEL_LABEL_SET/HEGEL_LABEL_SET_
  # ELEMENT are placed correctly. min_size: 1 forces at least one element
  # draw per set (min_size: 0 would let both sets shrink to empty without
  # ever exercising SET_ELEMENT). Set#inspect's own rendering differs
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
