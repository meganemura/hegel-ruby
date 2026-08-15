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

  # Every keyword #apply takes, defaulted the way Hegel.test itself defaults
  # them (nil except report_multiple_failures, which Hegel::Runner.run
  # always calls false rather than leaving nil -- see its own comment).
  # Tests below override only the keyword under test, through #apply_with,
  # so each one reads as "this keyword, with everything else left alone".
  DEFAULT_KEYWORDS = {
    test_cases: nil, seed: nil, derandomize: nil, verbosity: nil,
    database: nil, database_key: nil, phases: nil, suppress_health_check: nil,
    report_multiple_failures: false
  }.freeze

  def apply_with(fake = @fake, **overrides)
    Hegel::Settings.apply(fake, @ctx, @settings, **DEFAULT_KEYWORDS.merge(overrides))
  end

  def test_apply_calls_no_setter_when_every_optional_keyword_is_nil
    apply_with

    assert_empty @fake.settings_test_cases_calls
    assert_empty @fake.settings_seed_calls
    assert_empty @fake.settings_derandomize_calls
    assert_empty @fake.settings_verbosity_calls
    assert_empty @fake.settings_database_key_calls
    assert_empty @fake.settings_phases_calls
    assert_empty @fake.settings_suppress_health_check_calls
  end

  def test_apply_writes_test_cases_when_given
    apply_with(test_cases: 42)

    assert_equal [42], @fake.settings_test_cases_calls
  end

  def test_apply_writes_seed_with_has_seed_true_when_given
    apply_with(seed: 7)

    assert_equal [[7, true]], @fake.settings_seed_calls
  end

  def test_apply_writes_derandomize_when_given
    apply_with(derandomize: true)

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

      apply_with(fake, verbosity: symbol)

      assert_equal [code], fake.settings_verbosity_calls
    end
  end

  def test_apply_raises_on_an_unknown_verbosity_symbol_and_calls_no_setter
    error = assert_raises(Hegel::Error) { apply_with(verbosity: :loud) }

    assert_includes error.message, "loud"
    assert_empty @fake.settings_verbosity_calls
  end

  # The mandatory row of Hegel::Settings.apply_database's table: neither
  # keyword given still calls settings_set_database with "", matching every
  # Hegel.test call before database:/database_key: existed (see
  # docs/adr/0009).
  def test_apply_passes_an_empty_string_to_settings_set_database_when_neither_database_keyword_is_given
    apply_with

    assert_equal [""], @fake.settings_database_calls
    assert_empty @fake.settings_database_key_calls
  end

  # database: alone is the row the table forbids: it would otherwise store
  # under a key no caller chose, so this raises instead of guessing one.
  def test_apply_raises_when_database_is_given_without_database_key
    error = assert_raises(Hegel::Error) { apply_with(database: "/tmp/somewhere") }

    assert_includes error.message, "hegel: "
    assert_includes error.message, "database_key"
    assert_empty @fake.settings_database_calls
  end

  # database_key: alone calls only settings_set_database_key, leaving
  # settings_set_database uncalled so the engine's own default path applies.
  def test_apply_calls_only_settings_set_database_key_when_database_key_is_given_alone
    apply_with(database_key: "my-property")

    assert_empty @fake.settings_database_calls
    assert_equal ["my-property"], @fake.settings_database_key_calls
  end

  # Both given calls settings_set_database with the caller's own path, then
  # settings_set_database_key with the caller's own key.
  def test_apply_calls_both_database_setters_when_both_are_given
    apply_with(database: "/tmp/somewhere", database_key: "my-property")

    assert_equal ["/tmp/somewhere"], @fake.settings_database_calls
    assert_equal ["my-property"], @fake.settings_database_key_calls
  end

  def test_apply_ors_every_phase_symbol_given_into_one_mask
    apply_with(phases: %i[explicit reuse generate target shrink])

    assert_equal [Hegel::LibHegel::HEGEL_PHASE_ALL], @fake.settings_phases_calls
  end

  def test_apply_passes_a_single_phase_bit_when_only_one_symbol_is_given
    apply_with(phases: [:generate])

    assert_equal [Hegel::LibHegel::HEGEL_PHASE_GENERATE], @fake.settings_phases_calls
  end

  def test_apply_raises_on_an_unknown_phase_symbol_and_names_the_accepted_ones
    error = assert_raises(Hegel::Error) { apply_with(phases: [:generate, :warp_speed]) }

    assert_includes error.message, "warp_speed"
    Hegel::Settings::PHASE_CODES.each_key { |symbol| assert_includes error.message, symbol.inspect }
    assert_empty @fake.settings_phases_calls
  end

  # Mask 0 has not been measured against libhegel (see
  # Hegel::Settings.apply_phases's own comment), so an empty Array raises
  # rather than silently meaning "no phases".
  def test_apply_raises_on_an_empty_phases_array
    error = assert_raises(Hegel::Error) { apply_with(phases: []) }

    assert_includes error.message, "hegel: "
    assert_empty @fake.settings_phases_calls
  end

  def test_apply_ors_every_health_check_symbol_given_into_one_mask
    apply_with(suppress_health_check: %i[filter_too_much too_slow test_cases_too_large large_initial_test_case])

    expected = Hegel::LibHegel::HEGEL_HC_FILTER_TOO_MUCH | Hegel::LibHegel::HEGEL_HC_TOO_SLOW |
      Hegel::LibHegel::HEGEL_HC_TEST_CASES_TOO_LARGE | Hegel::LibHegel::HEGEL_HC_LARGE_INITIAL_TEST_CASE
    assert_equal [expected], @fake.settings_suppress_health_check_calls
  end

  def test_apply_passes_a_single_health_check_bit_when_only_one_symbol_is_given
    apply_with(suppress_health_check: [:filter_too_much])

    assert_equal [Hegel::LibHegel::HEGEL_HC_FILTER_TOO_MUCH], @fake.settings_suppress_health_check_calls
  end

  def test_apply_raises_on_an_unknown_health_check_symbol_and_names_the_accepted_ones
    error = assert_raises(Hegel::Error) { apply_with(suppress_health_check: [:filter_too_much, :too_slow_by_half]) }

    assert_includes error.message, "too_slow_by_half"
    Hegel::Settings::HEALTH_CHECK_CODES.each_key { |symbol| assert_includes error.message, symbol.inspect }
    assert_empty @fake.settings_suppress_health_check_calls
  end

  # Aligned with phases:' own empty-Array rule (see
  # Hegel::Settings.apply_suppress_health_check's own comment), even though
  # nil already means "no suppression" for this keyword.
  def test_apply_raises_on_an_empty_suppress_health_check_array
    error = assert_raises(Hegel::Error) { apply_with(suppress_health_check: []) }

    assert_includes error.message, "hegel: "
    assert_empty @fake.settings_suppress_health_check_calls
  end

  def test_apply_calls_settings_set_report_multiple_failures_with_false_by_default
    apply_with

    assert_equal [false], @fake.settings_report_multiple_failures_calls
  end

  def test_apply_calls_settings_set_report_multiple_failures_with_the_given_value
    apply_with(report_multiple_failures: true)

    assert_equal [true], @fake.settings_report_multiple_failures_calls
  end
end
