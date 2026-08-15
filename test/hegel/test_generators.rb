# frozen_string_literal: true

require "test_helper"
require "support/conformance"
require "date"
require "ipaddr"
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

  # ---- from_regex ----

  # fullmatch: false (the default): the drawn string only has to contain a
  # match, not equal one, so this checks for the pattern anywhere in the
  # result rather than anchoring it. "[a-z]{3}" is simple enough to mean
  # the same thing in Python re syntax (what the engine draws against) and
  # Ruby's Regexp syntax (what this assertion checks with), per the task's
  # own decision record.
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

  # Construction alone must not raise (a Regexp is a legal, if useless,
  # argument to build a generator from); only the draw below does.
  def test_from_regex_pattern_must_be_a_string_raises_at_draw_time
    generator = from_regex(/[a-z]{3}/)

    assert_kind_of Hegel::Generator, generator
    error = assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
    assert_includes error.message, "must be a String"
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

  # This layer does not validate max_length itself (see the task's own
  # decision record); hegel_string_generator_domain rejects a value
  # outside its documented 4..=255 range, and LibHegel.check! translates
  # that HEGEL_E_INVALID_ARG into this Hegel::Error.
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

  # This layer does not validate version itself (see the task's own
  # decision record); hegel_generate_uuid rejects a value outside its
  # documented 0..15 range, and LibHegel.check! translates that
  # HEGEL_E_INVALID_ARG into this Hegel::Error, the same division of labor
  # #domains follows for its own out-of-range max_length.
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
