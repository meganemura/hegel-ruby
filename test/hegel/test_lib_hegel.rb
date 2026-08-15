# frozen_string_literal: true

require "test_helper"
require "hegel/lib_hegel"
require "hegel/lib_hegel/real"
require "support/fake_lib_hegel"
require "stringio"
require "fiddle/import"

class TestLibHegel < Minitest::Test
  def test_stop_test_and_assume_failed_do_not_inherit_standard_error
    refute_includes Hegel::StopTest.ancestors, StandardError
    refute_includes Hegel::AssumeFailed.ancestors, StandardError
    assert_includes Hegel::StopTest.ancestors, Exception
    assert_includes Hegel::AssumeFailed.ancestors, Exception
  end

  def test_real_opens_libhegel_and_reports_the_pinned_version
    real = Hegel::LibHegel::Real.new
    version = Hegel::LibHegel.with_context(real) { |ctx| real.version(ctx) }
    assert_equal Hegel::LIBHEGEL_VERSION, version
  end

  def test_real_context_last_error_is_empty_after_a_successful_call
    real = Hegel::LibHegel::Real.new
    Hegel::LibHegel.with_context(real) do |ctx|
      real.version(ctx)
      assert_equal "", real.context_last_error(ctx)
    end
  end

  def test_real_context_free_is_a_no_op_on_nil
    real = Hegel::LibHegel::Real.new
    assert_nil real.context_free(nil)
  end

  def test_real_does_not_warn_when_the_loaded_version_matches
    io = StringIO.new
    Hegel::LibHegel::Real.new(io: io)
    assert_empty io.string
  end

  def test_with_context_yields_the_context_and_frees_it_on_a_normal_return
    fake = Hegel::LibHegel::Fake.new
    yielded_ctx = nil

    result = Hegel::LibHegel.with_context(fake) do |ctx|
      yielded_ctx = ctx
      :block_result
    end

    assert_equal :block_result, result
    assert_includes fake.freed_contexts, yielded_ctx
  end

  def test_with_context_frees_the_context_even_when_the_block_raises
    fake = Hegel::LibHegel::Fake.new
    raised_ctx = nil

    assert_raises(RuntimeError) do
      Hegel::LibHegel.with_context(fake) do |ctx|
        raised_ctx = ctx
        raise "boom"
      end
    end

    assert_includes fake.freed_contexts, raised_ctx
  end

  def test_fake_context_free_records_a_nil_context
    fake = Hegel::LibHegel::Fake.new
    fake.context_free(nil)
    assert_includes fake.freed_contexts, nil
  end

  def test_check_does_nothing_on_hegel_ok
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    assert_nil Hegel::LibHegel.check!(fake, ctx, Hegel::LibHegel::HEGEL_OK)
  end

  def test_check_translates_every_documented_error_code
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.last_error = "boom from libhegel"

    {
      Hegel::LibHegel::HEGEL_E_STOP_TEST => Hegel::StopTest,
      Hegel::LibHegel::HEGEL_E_ASSUME => Hegel::AssumeFailed,
      Hegel::LibHegel::HEGEL_E_BACKEND => Hegel::Error,
      Hegel::LibHegel::HEGEL_E_INVALID_ARG => Hegel::Error,
      Hegel::LibHegel::HEGEL_E_CONCURRENT_USE => Hegel::Error
    }.each do |code, klass|
      error = assert_raises(klass) { Hegel::LibHegel.check!(fake, ctx, code) }
      code_name = Hegel::LibHegel::CODE_NAMES.fetch(code)
      assert_includes error.message, "#{code_name} (#{code}): boom from libhegel"
    end
  end

  # An engine newer than the pinned one can answer with a code these bindings
  # have no name for. The engine's own diagnostic has to survive that.
  def test_check_reports_a_code_it_has_no_name_for
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.last_error = "boom from a newer engine"

    unnamed = Hegel::LibHegel::CODE_NAMES.keys.min - 1
    error = assert_raises(Hegel::Error) { Hegel::LibHegel.check!(fake, ctx, unnamed) }

    assert_includes error.message, "unknown result code (#{unnamed}): boom from a newer engine"
  end

  def test_fake_version_returns_the_configured_version_on_ok
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.version = "9.9.9"
    assert_equal "9.9.9", fake.version(ctx)
  end

  def test_fake_version_raises_via_check_on_a_configured_error_code
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.version_code = Hegel::LibHegel::HEGEL_E_BACKEND
    assert_raises(Hegel::Error) { fake.version(ctx) }
  end

  def test_warn_on_version_mismatch_warns_without_raising
    fake = Hegel::LibHegel::Fake.new
    fake.version = "9.9.9"
    ctx = fake.context_new
    io = StringIO.new

    Hegel::LibHegel.warn_on_version_mismatch(fake, ctx, io: io)

    assert_includes io.string, "9.9.9"
    assert_includes io.string, Hegel::LIBHEGEL_VERSION
  end

  def test_warn_on_version_mismatch_is_silent_on_a_match
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    io = StringIO.new

    Hegel::LibHegel.warn_on_version_mismatch(fake, ctx, io: io)

    assert_empty io.string
  end

  def test_real_and_fake_respond_to_every_libhegel_method
    real = Hegel::LibHegel::Real.new
    fake = Hegel::LibHegel::Fake.new

    Hegel::LibHegel::METHODS.each do |method_name|
      assert_respond_to real, method_name
      assert_respond_to fake, method_name
    end
  end

  def test_real_settings_free_run_free_and_test_case_free_are_no_ops_on_nil
    real = Hegel::LibHegel::Real.new
    assert_nil real.settings_free(nil, nil)
    assert_nil real.run_free(nil, nil)
    assert_nil real.test_case_free(nil, nil)
  end

  # Exercises every settings setter, hegel_run_start, and a full
  # hegel_next_test_case loop against the real engine, marking every case
  # VALID and freeing every handle it opens (settings, run, each test
  # case). The database is disabled ("") so the run leaves nothing on
  # disk.
  def test_real_run_loop_marks_every_case_valid_and_frees_every_handle
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 3)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_seed(ctx, settings, 42, true)
      real.settings_set_derandomize(ctx, settings, true)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      cases_seen = 0
      loop do
        tc = real.next_test_case(ctx, run)
        break if tc.nil?

        cases_seen += 1
        real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, tc)
      end

      real.run_free(ctx, run)
      assert_operator cases_seen, :>, 0
    end
  end

  # hegel_generate_boolean and hegel_generate_integer's documented
  # boundary behaviour: p = 0.0 / 1.0 always yield false / true without
  # consuming entropy, has_forced forces the result at a p that allows it,
  # and min_value == max_value always yields that value.
  def test_real_generate_boolean_and_generate_integer_at_their_bounds
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      assert_equal false, real.generate_boolean(ctx, tc, 0.0, false, false)
      assert_equal true, real.generate_boolean(ctx, tc, 1.0, false, false)
      assert_equal true, real.generate_boolean(ctx, tc, 0.5, true, true)
      assert_equal 5, real.generate_integer(ctx, tc, 5, 5)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # min_value == max_value pins hegel_generate_integer_big's own byte
  # convention against the engine's own interpretation, not just this
  # binding's encode/decode as each other's inverse (see
  # test_encode_integer_le_and_decode_integer_le_round_trip's own comment on
  # why round-tripping alone cannot catch that). Covers a bound past
  # int64_t's positive and negative edges, and past 2**64, both signs. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_generate_integer_big_at_degenerate_bounds_pins_the_byte_convention
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      assert_equal 2**100, real.generate_integer_big(ctx, tc, 2**100, 2**100)
      assert_equal(-(2**63) - 1, real.generate_integer_big(ctx, tc, -(2**63) - 1, -(2**63) - 1))
      assert_equal 2**64, real.generate_integer_big(ctx, tc, 2**64, 2**64)
      assert_equal(-(2**100), real.generate_integer_big(ctx, tc, -(2**100), -(2**100)))

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # An asymmetric range -- min_value's own minimal encoding (1 byte) is
  # shorter than max_value's (13 bytes) -- drives out_value_cap above
  # min_value_len, and a range that spans zero exercises both a negative
  # and a non-negative draw landing correctly in range. The database is
  # disabled ("") so the run leaves nothing on disk.
  def test_real_generate_integer_big_stays_within_an_asymmetric_range
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      20.times do
        value = real.generate_integer_big(ctx, tc, -1, 2**100)
        assert_includes(-1..(2**100), value)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_generate_integer_big_stop_test_translates_to_hegel_stop_test
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_integer_big_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { fake.generate_integer_big(ctx, Object.new, -(2**100), 2**100) }
  end

  def test_fake_generate_integer_big_returns_the_configured_value
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_integer_big_value = 2**100

    assert_equal 2**100, fake.generate_integer_big(ctx, Object.new, -(2**100), 2**100)
  end

  def test_fake_generate_boolean_stop_test_translates_to_hegel_stop_test
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_boolean_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { fake.generate_boolean(ctx, Object.new, 0.5, false, false) }
  end

  def test_fake_generate_integer_stop_test_translates_to_hegel_stop_test
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_integer_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { fake.generate_integer(ctx, Object.new, 0, 10) }
  end

  # LibHegel.encode_integer_le / .decode_integer_le's own documented
  # two's-complement little-endian convention, round-tripped over zero,
  # both signs, and the byte-length boundaries a naive "bits then round up"
  # formula could get wrong: single-byte edges (127/128, -128/-129), the
  # int64_t edges IntegerGenerator dispatches on, and a value past both.
  # Round-tripping alone cannot catch a convention that is self-consistent
  # but wrong (encoding big-endian in both directions would still pass this
  # loop); see test_real_generate_integer_big_at_degenerate_bounds_pins_the_
  # byte_convention below for the check against the engine's own
  # interpretation.
  def test_encode_integer_le_and_decode_integer_le_round_trip
    [
      0, 1, -1, 127, 128, -128, -129, 255, 256, -255, -256,
      (2**63) - 1, 2**63, -(2**63), -(2**63) - 1,
      2**64, -(2**64), 2**100, -(2**100)
    ].each do |n|
      bytes = Hegel::LibHegel.encode_integer_le(n)
      assert_equal n, Hegel::LibHegel.decode_integer_le(bytes), "round-trip failed for #{n}"
    end
  end

  # .decode_integer_le accepts a buffer longer than the value's own minimal
  # encoding, sign-filled the way hegel_generate_integer_big's out_value is
  # documented to be, and must still decode to the same value either way.
  def test_decode_integer_le_accepts_a_sign_filled_longer_buffer
    assert_equal 5, Hegel::LibHegel.decode_integer_le(Hegel::LibHegel.encode_integer_le(5) + "\x00".b * 3)
    assert_equal(-5, Hegel::LibHegel.decode_integer_le(Hegel::LibHegel.encode_integer_le(-5) + "\xFF".b * 3))
  end

  def test_fake_mark_complete_records_origin_only_when_passed
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    tc = Object.new

    fake.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_INTERESTING, "origin.rb:1")
    fake.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)

    assert_equal [Hegel::LibHegel::HEGEL_STATUS_INTERESTING, Hegel::LibHegel::HEGEL_STATUS_VALID],
      fake.marked_statuses
    assert_equal ["origin.rb:1", nil], fake.marked_origins
  end

  def test_fake_next_test_case_yields_the_configured_count_then_nil
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.test_case_count = 2

    first = fake.next_test_case(ctx, nil)
    second = fake.next_test_case(ctx, nil)
    third = fake.next_test_case(ctx, nil)

    refute_nil first
    refute_nil second
    assert_nil third
  end

  def test_fake_run_start_returns_nil_when_configured_to
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.run_start_returns_nil = true

    assert_nil fake.run_start(ctx, Object.new)
  end

  def test_real_run_result_free_and_failure_free_are_no_ops_on_nil
    real = Hegel::LibHegel::Real.new
    assert_nil real.run_result_free(nil, nil)
    assert_nil real.failure_free(nil, nil)
  end

  # A run where every case is marked VALID has no counterexample: status
  # comes back HEGEL_RUN_STATUS_PASSED and hegel_run_result_error's
  # out-parameter is NULL (nil here), since the run completed normally.
  # hegel_run_result is read before hegel_run_free and everything but
  # hegel_run_result_free is read after it, confirming the header's claim
  # that the copy stays valid past the run's own lifetime. The database is
  # disabled ("") so the run leaves nothing on disk.
  def test_real_passed_run_reports_passed_status_and_nil_error_after_run_free
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 3)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      loop do
        tc = real.next_test_case(ctx, run)
        break if tc.nil?

        real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, tc)
      end

      result = real.run_result(ctx, run)
      real.run_free(ctx, run)

      assert_equal Hegel::LibHegel::HEGEL_RUN_STATUS_PASSED, real.run_result_status(ctx, result)
      assert_nil real.run_result_error(ctx, result)
      assert_equal 0, real.run_result_failure_count(ctx, result)

      real.run_result_free(ctx, result)
    end
  end

  # Every case is marked INTERESTING under the same origin, so libhegel
  # groups every shrink probe as one bug and the run always fails. Reads
  # hegel_run_result's status, failure count, and each failure's origin
  # and reproduction blob, then replays that blob through
  # hegel_test_case_from_blob (no run handle or run loop needed for
  # replay, per the header). The database is disabled ("") so the run
  # leaves nothing on disk.
  def test_real_failing_run_reports_failed_status_and_a_replayable_blob
    real = Hegel::LibHegel::Real.new
    origin = "hegel-ruby-test-origin"

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 3)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      loop do
        tc = real.next_test_case(ctx, run)
        break if tc.nil?

        real.generate_integer(ctx, tc, 0, 100)
        real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_INTERESTING, origin)
        real.test_case_free(ctx, tc)
      end

      result = real.run_result(ctx, run)
      real.run_free(ctx, run)

      assert_equal Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED, real.run_result_status(ctx, result)

      count = real.run_result_failure_count(ctx, result)
      assert_operator count, :>=, 1

      count.times do |index|
        failure = real.run_result_failure(ctx, result, index)
        assert_includes real.failure_origin(ctx, failure), origin

        blob = real.failure_reproduction_blob(ctx, failure)
        assert_kind_of String, blob

        # Marking the replayed handle complete (rather than freeing it
        # right away) proves it is a live test case, not merely a NULL
        # out.ptr that test_case_free's documented no-op-on-NULL contract
        # would silently accept.
        replay_settings = real.settings_new(ctx)
        real.settings_set_verbosity(ctx, replay_settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
        real.settings_set_database(ctx, replay_settings, "")
        replayed = real.test_case_from_blob(ctx, replay_settings, blob)
        real.mark_complete(ctx, replayed, Hegel::LibHegel::HEGEL_STATUS_INTERESTING, origin)
        real.test_case_free(ctx, replayed)
        real.settings_free(ctx, replay_settings)

        real.failure_free(ctx, failure)
      end

      real.run_result_free(ctx, result)
    end
  end

  # The header documents HEGEL_E_INVALID_ARG for a blob that is corrupt,
  # non-UTF-8, or from an incompatible Hegel version; a plain string that
  # was never produced by hegel_failure_reproduction_blob hits the same
  # "corrupt" case.
  def test_real_test_case_from_blob_raises_on_a_corrupt_blob
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      assert_raises(Hegel::Error) { real.test_case_from_blob(ctx, settings, "not a blob") }

      real.settings_free(ctx, settings)
    end
  end

  # #run_result_error and #failure_reproduction_blob share the ternary
  # that copies libhegel's borrowed string or reports nil for a NULL
  # out-parameter (LibHegel::Real#nullable_out_string); the real-engine
  # tests above exercise its non-nil branch (a failure's blob) and its nil
  # branch (a passed run's error). This confirms the Fake can model the
  # nil-blob case, distinct from that ternary, for logic built on this
  # boundary that needs to be testable without the native engine.
  def test_fake_failure_reproduction_blob_returns_nil_when_configured_to
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.failure_origins = ["origin.rb:1"]
    fake.failure_blobs = [nil]

    failure = fake.run_result_failure(ctx, Object.new, 0)

    assert_equal "origin.rb:1", fake.failure_origin(ctx, failure)
    assert_nil fake.failure_reproduction_blob(ctx, failure)
  end

  def test_real_collection_free_string_generator_free_and_generate_string_result_free_are_no_ops_on_nil
    real = Hegel::LibHegel::Real.new
    assert_nil real.collection_free(nil, nil)
    assert_nil real.string_generator_free(nil, nil)
    assert_nil real.generate_string_result_free(nil, nil)
  end

  # hegel_start_span / hegel_stop_span pair around a draw, per the header
  # ("Pair with exactly one hegel_stop_span call"). Confirms a span can be
  # opened, drawn inside, and closed without discarding it. The database
  # is disabled ("") so the run leaves nothing on disk.
  def test_real_start_span_and_stop_span_around_a_draw
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      assert_nil real.start_span(ctx, tc, Hegel::LibHegel::HEGEL_LABEL_TUPLE)
      value = real.generate_integer(ctx, tc, 1, 10)
      assert_includes(1..10, value)
      assert_nil real.stop_span(ctx, tc, false)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # Drives hegel_collection_more in a loop, drawing one element per true,
  # until it answers false, matching the header's documented usage. The
  # drawn element count must land within [min_size, max_size]. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_collection_more_loop_stays_within_the_configured_size_bounds
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      collection = real.new_collection(ctx, tc, 2, 4)
      count = 0
      while real.collection_more(ctx, tc, collection)
        real.generate_integer(ctx, tc, 1, 10)
        count += 1
      end
      real.collection_free(ctx, collection)

      assert_includes(2..4, count)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # hegel_collection_reject tells libhegel the last element drawn under a
  # collection is invalid. Rejecting the only element of a min_size: 1,
  # max_size: 1 collection means the collection is not yet satisfied, so
  # #collection_more must answer true again for a second, accepted draw
  # before it finally answers false. The database is disabled ("") so the
  # run leaves nothing on disk.
  def test_real_collection_reject_keeps_the_collection_unsatisfied
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      collection = real.new_collection(ctx, tc, 1, 1)

      assert_equal true, real.collection_more(ctx, tc, collection)
      real.generate_integer(ctx, tc, 1, 10)
      assert_nil real.collection_reject(ctx, tc, collection, "rejected by test")

      assert_equal true, real.collection_more(ctx, tc, collection)
      real.generate_integer(ctx, tc, 1, 10)
      assert_equal false, real.collection_more(ctx, tc, collection)

      real.collection_free(ctx, collection)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # min_value == max_value always yields that value, the same documented
  # boundary #test_real_generate_boolean_and_generate_integer_at_their_bounds
  # exercises for hegel_generate_boolean / hegel_generate_integer. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_generate_float_at_a_degenerate_bound
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      value = real.generate_float(
        ctx, tc, 64, 3.5, 3.5, false, false, false, false,
        Hegel::LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED
      )
      assert_equal 3.5, value

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # allow_nan: false must never draw NaN, over enough draws to make a
  # missed exclusion unlikely to go unnoticed. The database is disabled
  # ("") so the run leaves nothing on disk.
  def test_real_generate_float_never_draws_nan_when_allow_nan_is_false
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      100.times do
        value = real.generate_float(
          ctx, tc, 64, -Float::INFINITY, Float::INFINITY, false, true, false, false,
          Hegel::LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED
        )
        refute value.nan?
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # Draws a text string within [min_size, max_size] and confirms the
  # returned String reports UTF-8 encoding, per the header's "data points
  # to len bytes of UTF-8". The database is disabled ("") so the run
  # leaves nothing on disk.
  def test_real_generate_string_returns_a_utf8_string_within_the_configured_size_bounds
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      generator = real.string_generator_text(ctx, min_size: 2, max_size: 5)
      begin
        value = real.generate_string(ctx, tc, generator)
        assert_equal Encoding::UTF_8, value.encoding
        assert value.valid_encoding?
        assert_includes(2..5, value.length)
      ensure
        real.string_generator_free(ctx, generator)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # hegel_generate_string's result is documented as not NUL-terminated
  # and possibly containing interior NUL bytes, since the drawn alphabet
  # can include U+0000. Forcing min_codepoint: 0, max_codepoint: 0 draws
  # from an alphabet of exactly U+0000, so a correct implementation reads
  # every byte via len; reading with Fiddle::Pointer#to_s (no length,
  # stopping at the first NUL) would instead return an empty string. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_generate_string_reads_the_full_length_including_interior_nul_bytes
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      generator = real.string_generator_text(ctx, min_size: 3, max_size: 3, min_codepoint: 0, max_codepoint: 0)
      begin
        value = real.generate_string(ctx, tc, generator)
        assert_equal 3, value.bytesize
        assert_equal "\u0000\u0000\u0000", value
      ensure
        real.string_generator_free(ctx, generator)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_collection_more_yields_true_the_configured_count_then_false
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.collection_more_count = 2

    first = fake.collection_more(ctx, nil, nil)
    second = fake.collection_more(ctx, nil, nil)
    third = fake.collection_more(ctx, nil, nil)

    assert_equal true, first
    assert_equal true, second
    assert_equal false, third
  end

  def test_fake_run_result_status_and_error_return_the_configured_values
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_ERROR
    fake.run_result_error_value = "a failed health check"

    assert_equal Hegel::LibHegel::HEGEL_RUN_STATUS_ERROR, fake.run_result_status(ctx, Object.new)
    assert_equal "a failed health check", fake.run_result_error(ctx, Object.new)
  end

  # hegel_generate_bytes returns a {uint8_t *data; size_t len} buffer, not
  # text: unlike #generate_string, the returned String must stay
  # Encoding::BINARY rather than being force-encoded UTF-8. The database
  # is disabled ("") so the run leaves nothing on disk.
  def test_real_generate_bytes_returns_binary_encoded_bytes_within_the_configured_size_bounds
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      value = real.generate_bytes(ctx, tc, 2, 5)
      assert_equal Encoding::BINARY, value.encoding
      assert_includes(2..5, value.bytesize)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_generate_bytes_stop_test_translates_to_hegel_stop_test
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_bytes_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { fake.generate_bytes(ctx, Object.new, 0, 10) }
  end

  # hegel_string_generator_email / _url / _domain each build a
  # hegel_string_generator_t*, freed and drawn the same way as the text
  # generator above (#string_generator_free / #generate_string): the
  # header documents no dedicated free or draw call for any of them. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_email_url_and_domain_generators_draw_strings
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      [
        real.string_generator_email(ctx),
        real.string_generator_url(ctx),
        real.string_generator_domain(ctx, 50)
      ].each do |generator|
        value = real.generate_string(ctx, tc, generator)
        assert_kind_of String, value
      ensure
        real.string_generator_free(ctx, generator)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # hegel_string_generator_domain's max_length is documented as valid in
  # 4..=255. Measured against libhegel 0.32.5: both ends outside that
  # range come back HEGEL_E_INVALID_ARG, translated here to Hegel::Error,
  # matching the header's "Returns ... HEGEL_E_INVALID_ARG for a
  # max_length that leaves no eligible top-level domains" (which also
  # covers the upper bound, past RFC 1035's 255-byte limit).
  def test_real_string_generator_domain_raises_on_max_length_out_of_range
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      assert_raises(Hegel::Error) { real.string_generator_domain(ctx, 3) }
      assert_raises(Hegel::Error) { real.string_generator_domain(ctx, 256) }
    end
  end

  # hegel_string_generator_regex's alphabet is optional (NULL). This draws
  # with no alphabet at all -- the default branch of #string_generator_regex's
  # optional argument -- while the next test below exercises the other
  # branch, passing one built from #string_generator_text. The database is
  # disabled ("") so the run leaves nothing on disk.
  def test_real_regex_generator_draws_without_an_alphabet
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      generator = real.string_generator_regex(ctx, "a+", true)
      begin
        value = real.generate_string(ctx, tc, generator)
        assert_kind_of String, value
      ensure
        real.string_generator_free(ctx, generator)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # The explicit-alphabet path #string_generator_regex's optional argument
  # is for: a text generator, built the same way #string_generator_text is
  # used everywhere else in this file, constrains the regex draw's padding
  # and wildcard characters. The database is disabled ("") so the run
  # leaves nothing on disk.
  def test_real_regex_generator_accepts_a_text_alphabet_generator
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      alphabet = real.string_generator_text(ctx, min_size: 1, max_size: 1, codec: "ascii")
      begin
        generator = real.string_generator_regex(ctx, "a+", false, alphabet)
        begin
          value = real.generate_string(ctx, tc, generator)
          assert_kind_of String, value
        ensure
          real.string_generator_free(ctx, generator)
        end
      ensure
        real.string_generator_free(ctx, alphabet)
      end

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_string_generator_regex_email_url_and_domain_translate_configured_error_codes
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new

    fake.string_generator_regex_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    assert_raises(Hegel::Error) { fake.string_generator_regex(ctx, "a+", false) }

    fake.string_generator_email_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    assert_raises(Hegel::Error) { fake.string_generator_email(ctx) }

    fake.string_generator_url_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    assert_raises(Hegel::Error) { fake.string_generator_url(ctx) }

    fake.string_generator_domain_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    assert_raises(Hegel::Error) { fake.string_generator_domain(ctx, 50) }
  end

  # hegel_generate_ipv4 / hegel_generate_ipv6 write into a caller-supplied
  # fixed-length buffer (4 and 16 bytes respectively) rather than an
  # out-parameter pointer, per the header. This layer returns the raw
  # bytes, not an IPAddr -- conversion is a future generator's job. The
  # database is disabled ("") so the run leaves nothing on disk.
  def test_real_generate_ipv4_and_generate_ipv6_return_the_documented_byte_lengths
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      ipv4 = real.generate_ipv4(ctx, tc)
      assert_equal 4, ipv4.bytesize
      assert_equal Encoding::BINARY, ipv4.encoding

      ipv6 = real.generate_ipv6(ctx, tc)
      assert_equal 16, ipv6.bytesize
      assert_equal Encoding::BINARY, ipv6.encoding

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_generate_ipv4_and_generate_ipv6_return_the_configured_values
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_ipv4_value = "\x01\x02\x03\x04".b
    fake.generate_ipv6_value = ("\x00" * 15 + "\x01").b

    assert_equal "\x01\x02\x03\x04".b, fake.generate_ipv4(ctx, Object.new)
    assert_equal ("\x00" * 15 + "\x01").b, fake.generate_ipv6(ctx, Object.new)
  end

  # hegel_generate_uuid writes into a caller-supplied 16-byte buffer, the
  # same fixed-buffer shape as #generate_ipv4/#generate_ipv6. has_version:
  # false draws unconstrained bytes; has_version: true forces the version
  # nibble (the top nibble of byte 6, per the header's "version nibble")
  # to the requested value. The database is disabled ("") so the run
  # leaves nothing on disk.
  def test_real_generate_uuid_returns_16_raw_bytes_and_a_forced_version_sets_its_nibble
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      unversioned = real.generate_uuid(ctx, tc, 0, false)
      assert_equal 16, unversioned.bytesize
      assert_equal Encoding::BINARY, unversioned.encoding

      versioned = real.generate_uuid(ctx, tc, 4, true)
      assert_equal 4, versioned.getbyte(6) >> 4

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # This layer does not validate version itself (see the task's own
  # decision record); hegel_generate_uuid rejects a value outside its
  # documented 0..15 range, and LibHegel.check! translates that
  # HEGEL_E_INVALID_ARG into this Hegel::Error, the same division of labor
  # #string_generator_domain follows for its own out-of-range max_length.
  # Unlike #string_generator_domain, this call draws (needs a live test
  # case, not just a context), so this opens a run the same way every
  # other draw test in this file does. The database is disabled ("") so
  # the run leaves nothing on disk.
  def test_real_generate_uuid_out_of_range_version_raises
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      assert_raises(Hegel::Error) { real.generate_uuid(ctx, tc, 16, true) }

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_INVALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  def test_fake_generate_uuid_stop_test_translates_to_hegel_stop_test
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_uuid_code = Hegel::LibHegel::HEGEL_E_STOP_TEST

    assert_raises(Hegel::StopTest) { fake.generate_uuid(ctx, Object.new, 4, true) }
  end

  def test_fake_generate_uuid_returns_the_configured_value
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_uuid_value = "\x01" * 16

    assert_equal "\x01" * 16, fake.generate_uuid(ctx, Object.new, 0, false)
  end

  # Hegel::TestCase's own wrappers for the native calls this file adds
  # bindings for above: real.rb only makes them callable, not reachable
  # from a Hegel::Generator#do_draw (see
  # .claude/skills/new-generator/SKILL.md, "bound is not the same as
  # callable"). Driven against the Fake since these are thin, unconditional
  # delegations to the same-named Hegel::LibHegel method -- nothing here
  # depends on the native engine.
  def test_test_case_generate_bytes_generate_ipv4_generate_ipv6_generate_uuid_and_generate_integer_big_delegate_to_impl
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_bytes_value = "\xAB\xCD".b
    fake.generate_ipv4_value = "\x01\x02\x03\x04".b
    fake.generate_ipv6_value = ("\x00" * 16).b
    fake.generate_uuid_value = "\x01" * 16
    fake.generate_integer_big_value = 2**100
    tc = Hegel::TestCase.new(fake, ctx, Object.new)

    assert_equal "\xAB\xCD".b, tc.generate_bytes(1, 5)
    assert_equal "\x01\x02\x03\x04".b, tc.generate_ipv4
    assert_equal ("\x00" * 16).b, tc.generate_ipv6
    assert_equal "\x01" * 16, tc.generate_uuid(0, false)
    assert_equal 2**100, tc.generate_integer_big(-(2**100), 2**100)
  end

  # Exercises both branches of #string_generator_regex's optional
  # +alphabet+ argument -- called with none (the default) and with an
  # explicit handle -- so this method's own default-argument branch is
  # covered from the TestCase layer, not just Real's.
  def test_test_case_string_generator_constructors_and_free_delegate_to_impl
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    tc = Hegel::TestCase.new(fake, ctx, Object.new)

    generators = [
      tc.string_generator_regex("a+", false),
      tc.string_generator_regex("a+", true, Object.new),
      tc.string_generator_email,
      tc.string_generator_url,
      tc.string_generator_domain(50)
    ]

    generators.each { |generator| refute_nil generator }
    generators.each { |generator| assert_nil tc.string_generator_free(generator) }
    assert_equal generators, fake.freed_string_generators
  end

  # hegel_date_t / hegel_time_t / hegel_datetime_t's own byte layout, which
  # LibHegel::Real#pack_date/#pack_time/#unpack_date/#unpack_time hardcode
  # as bit shifts (see docs/architecture.md, "Passing a struct by value").
  # Packing a struct into uint64 register(s) only reproduces the native
  # ABI's own call when the byte size and each field's offset match what
  # the compiled struct actually uses; a mismatch would not fail to draw --
  # it would draw a plausible-looking wrong value forever, since encoding
  # and decoding both apply the same wrong assumption to themselves,
  # consistently. This test computes size/offset independently, via
  # Fiddle's own C-ABI alignment rules applied to the three fields hegel.h
  # documents for each struct, rather than re-reading the bit-shift
  # constants in real.rb -- a mismatch between the two is what this test
  # exists to catch. Fiddle is confined to real.rb inside lib/ (see the
  # skill's own "git grep Fiddle lib/" checklist item, scoped to lib/, not
  # test/), so this reaches for it directly rather than through Real's
  # private packing methods.
  def test_hegel_date_time_and_datetime_struct_layout
    date_t = build_c_struct(["int32_t year", "uint8_t month", "uint8_t day"])
    time_t = build_c_struct(["uint8_t hour", "uint8_t minute", "uint8_t second", "uint32_t microsecond"])
    datetime_t = Fiddle::CStructBuilder.create(Fiddle::CStruct, [date_t, time_t], ["date", "time"])

    assert_equal 8, date_t.size
    assert_equal 0, date_t.offsetof("year")
    assert_equal 4, date_t.offsetof("month")
    assert_equal 5, date_t.offsetof("day")

    assert_equal 8, time_t.size
    assert_equal 0, time_t.offsetof("hour")
    assert_equal 1, time_t.offsetof("minute")
    assert_equal 2, time_t.offsetof("second")
    assert_equal 4, time_t.offsetof("microsecond")

    assert_equal 16, datetime_t.size
    assert_equal 0, datetime_t.offsetof("date")
    assert_equal 8, datetime_t.offsetof("time")
  end

  # hegel_generate_date / hegel_generate_time / hegel_generate_datetime each
  # take a struct by value, packed into uint64 register(s) by
  # LibHegel::Real#generate_date/#generate_time/#generate_datetime (see
  # docs/architecture.md, "Passing a struct by value"). min_value ==
  # max_value pins that packing against the engine's own interpretation,
  # not just this binding's own pack/unpack as each other's inverse (a
  # round trip alone cannot catch a self-consistent but wrong byte
  # convention -- see the skill's own note on why a degenerate draw against
  # the real engine is required). Exercises both ends of the conventional
  # full range, and one value with every field distinct (13:45:06.123456,
  # and that time embedded in a datetime): the boundary values alone are
  # swap-symmetric in minute/second (00 vs 00, 59 vs 59), so a
  # minute<->second packing bug would still pass them; a value with no two
  # fields sharing a digit is what catches that. The database is disabled
  # ("") so the run leaves nothing on disk.
  def test_real_generate_date_time_and_datetime_at_degenerate_bounds_pins_the_struct_packing
    real = Hegel::LibHegel::Real.new

    Hegel::LibHegel.with_context(real) do |ctx|
      settings = real.settings_new(ctx)
      real.settings_set_test_cases(ctx, settings, 1)
      real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      real.settings_set_database(ctx, settings, "")

      run = real.run_start(ctx, settings)
      real.settings_free(ctx, settings)

      tc = real.next_test_case(ctx, run)
      refute_nil tc

      assert_equal [1, 1, 1], real.generate_date(ctx, tc, [1, 1, 1], [1, 1, 1])
      assert_equal [9999, 12, 31], real.generate_date(ctx, tc, [9999, 12, 31], [9999, 12, 31])

      assert_equal [0, 0, 0, 0], real.generate_time(ctx, tc, [0, 0, 0, 0], [0, 0, 0, 0])
      assert_equal [23, 59, 59, 999_999], real.generate_time(ctx, tc, [23, 59, 59, 999_999], [23, 59, 59, 999_999])
      assert_equal [13, 45, 6, 123_456], real.generate_time(ctx, tc, [13, 45, 6, 123_456], [13, 45, 6, 123_456])

      min_dt = [[1, 1, 1], [0, 0, 0, 0]]
      max_dt = [[9999, 12, 31], [23, 59, 59, 999_999]]
      distinct_dt = [[2024, 3, 17], [13, 45, 6, 123_456]]
      assert_equal min_dt, real.generate_datetime(ctx, tc, *min_dt, *min_dt)
      assert_equal max_dt, real.generate_datetime(ctx, tc, *max_dt, *max_dt)
      assert_equal distinct_dt, real.generate_datetime(ctx, tc, *distinct_dt, *distinct_dt)

      real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
      real.test_case_free(ctx, tc)

      loop do
        next_tc = real.next_test_case(ctx, run)
        break if next_tc.nil?

        real.mark_complete(ctx, next_tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
        real.test_case_free(ctx, next_tc)
      end

      real.run_free(ctx, run)
    end
  end

  # Hegel::TestCase's own wrappers for hegel_generate_date/_time/_datetime,
  # the same "bound is not the same as callable" thin-delegation check
  # test_test_case_generate_bytes_generate_ipv4_generate_ipv6_generate_uuid_and_generate_integer_big_delegate_to_impl
  # already runs for the other native calls this file binds.
  def test_test_case_generate_date_generate_time_and_generate_datetime_delegate_to_impl
    fake = Hegel::LibHegel::Fake.new
    ctx = fake.context_new
    fake.generate_date_value = [2020, 1, 1]
    fake.generate_time_value = [13, 45, 6, 123_456]
    fake.generate_datetime_value = [[2020, 1, 1], [13, 45, 6, 123_456]]
    tc = Hegel::TestCase.new(fake, ctx, Object.new)

    assert_equal [2020, 1, 1], tc.generate_date([1, 1, 1], [9999, 12, 31])
    assert_equal [13, 45, 6, 123_456], tc.generate_time([0, 0, 0, 0], [23, 59, 59, 999_999])
    assert_equal [[2020, 1, 1], [13, 45, 6, 123_456]],
      tc.generate_datetime([1, 1, 1], [0, 0, 0, 0], [9999, 12, 31], [23, 59, 59, 999_999])
  end

  private

  # A fresh Fiddle::Importer-backed struct class for +fields+ (C type
  # declarations, e.g. "int32_t year"), so
  # test_hegel_date_time_and_datetime_struct_layout can ask Fiddle itself
  # for the size and per-field offset its own C-ABI alignment rules
  # produce, independent of any hardcoded number in this file or in
  # real.rb.
  def build_c_struct(fields)
    importer = Module.new
    importer.extend(Fiddle::Importer)
    importer.struct(fields)
  end
end
