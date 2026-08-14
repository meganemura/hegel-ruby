# frozen_string_literal: true

require "test_helper"
require "hegel/settings"
require "support/fake_lib_hegel"

class TestSettings < Minitest::Test
  def setup
    @fake = Hegel::LibHegel::Fake.new
    @ctx = @fake.context_new
    @settings = @fake.settings_new(@ctx)
  end

  def test_apply_calls_no_setter_when_every_keyword_is_nil
    Hegel::Settings.apply(@fake, @ctx, @settings, test_cases: nil, seed: nil, derandomize: nil, verbosity: nil)

    assert_empty @fake.settings_test_cases_calls
    assert_empty @fake.settings_seed_calls
    assert_empty @fake.settings_derandomize_calls
    assert_empty @fake.settings_verbosity_calls
  end

  def test_apply_writes_test_cases_when_given
    Hegel::Settings.apply(@fake, @ctx, @settings, test_cases: 42, seed: nil, derandomize: nil, verbosity: nil)

    assert_equal [42], @fake.settings_test_cases_calls
  end

  def test_apply_writes_seed_with_has_seed_true_when_given
    Hegel::Settings.apply(@fake, @ctx, @settings, test_cases: nil, seed: 7, derandomize: nil, verbosity: nil)

    assert_equal [[7, true]], @fake.settings_seed_calls
  end

  def test_apply_writes_derandomize_when_given
    Hegel::Settings.apply(@fake, @ctx, @settings, test_cases: nil, seed: nil, derandomize: true, verbosity: nil)

    assert_equal [true], @fake.settings_derandomize_calls
  end

  def test_apply_maps_every_verbosity_symbol_to_its_hegel_verbosity_t_code
    {
      quiet: Hegel::LibHegel::HEGEL_VERBOSITY_QUIET,
      normal: Hegel::LibHegel::HEGEL_VERBOSITY_NORMAL,
      verbose: Hegel::LibHegel::HEGEL_VERBOSITY_VERBOSE,
      debug: Hegel::LibHegel::HEGEL_VERBOSITY_DEBUG
    }.each do |symbol, code|
      fake = Hegel::LibHegel::Fake.new
      ctx = fake.context_new
      settings = fake.settings_new(ctx)

      Hegel::Settings.apply(fake, ctx, settings, test_cases: nil, seed: nil, derandomize: nil, verbosity: symbol)

      assert_equal [code], fake.settings_verbosity_calls
    end
  end

  def test_apply_raises_on_an_unknown_verbosity_symbol_and_calls_no_setter
    error = assert_raises(Hegel::Error) do
      Hegel::Settings.apply(@fake, @ctx, @settings, test_cases: nil, seed: nil, derandomize: nil, verbosity: :loud)
    end

    assert_includes error.message, "loud"
    assert_empty @fake.settings_verbosity_calls
  end
end
