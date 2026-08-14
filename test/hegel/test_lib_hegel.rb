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
end
