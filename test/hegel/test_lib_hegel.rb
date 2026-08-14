# frozen_string_literal: true

require "test_helper"
require "hegel/lib_hegel"
require "hegel/lib_hegel/real"
require "support/fake_lib_hegel"
require "stringio"

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
end
