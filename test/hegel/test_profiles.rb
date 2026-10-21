# frozen_string_literal: true

require "test_helper"
require "hegel/settings"
require "support/fake_lib_hegel"
require "securerandom"
require "stringio"

class TestProfiles < Minitest::Test
  ENGINE_VARIABLES = %w[HEGEL_PRINT_BLOB HEGEL_DEFAULT_PROFILE].freeze

  def setup
    @fake = Hegel::LibHegel::Fake.new
    @saved_env = ENGINE_VARIABLES.to_h { |name| [name, ENV.fetch(name, nil)] }
    ENGINE_VARIABLES.each { |name| ENV.delete(name) }
  end

  def teardown
    @saved_env.each { |name, value| ENV[name] = value }
  end

  def test_register_profile_starts_from_the_default_profile_when_none_is_named
    assert_nil Hegel::Settings.register_profile("nightly", impl: @fake)

    assert_empty @fake.settings_new_for_profile_calls
    assert_equal ["nightly"], @fake.settings_register_profile_calls.map(&:first)
  end

  def test_register_profile_starts_from_the_named_profile
    Hegel::Settings.register_profile("nightly", profile: "ci", impl: @fake)

    assert_equal ["ci"], @fake.settings_new_for_profile_calls
  end

  def test_register_profile_applies_the_keywords_before_it_registers
    Hegel::Settings.register_profile("nightly", test_cases: 10_000, print_blob: false, impl: @fake)

    assert_equal [10_000], @fake.settings_test_cases_calls
    assert_equal [false], @fake.settings_print_blob_calls
    assert_empty @fake.settings_seed_calls
  end

  def test_register_profile_registers_the_handle_it_built_and_then_frees_it
    Hegel::Settings.register_profile("nightly", impl: @fake)

    registered = @fake.settings_register_profile_calls.fetch(0).last
    assert_equal [registered], @fake.freed_settings
  end

  def test_register_profile_passes_database_through_unchanged
    Hegel::Settings.register_profile("a", database: "/some/dir", impl: @fake)
    Hegel::Settings.register_profile("b", database: "", impl: @fake)
    Hegel::Settings.register_profile("c", impl: @fake)

    assert_equal ["/some/dir", ""], @fake.settings_database_calls
    assert_empty @fake.settings_database_key_calls
  end

  def test_register_profile_leaves_report_multiple_failures_alone_unless_given
    Hegel::Settings.register_profile("a", impl: @fake)
    assert_empty @fake.settings_report_multiple_failures_calls

    Hegel::Settings.register_profile("b", report_multiple_failures: false, impl: @fake)
    assert_equal [false], @fake.settings_report_multiple_failures_calls
  end

  def test_register_profile_rejects_database_key
    assert_raises(ArgumentError) { Hegel::Settings.register_profile("a", database_key: "k", impl: @fake) }
    assert_raises(ArgumentError) { Hegel::Settings.register_profile("a", no_such_keyword: 1, impl: @fake) }
  end

  def test_register_profile_frees_the_handle_and_the_context_when_a_keyword_is_invalid
    assert_raises(Hegel::Error) { Hegel::Settings.register_profile("a", verbosity: :loud, impl: @fake) }

    assert_empty @fake.settings_register_profile_calls
    assert_equal 1, @fake.freed_settings.size
    assert_equal 1, @fake.freed_contexts.size
  end

  def test_register_profile_frees_the_handle_and_the_context_when_registration_fails
    @fake.settings_register_profile_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { Hegel::Settings.register_profile("base", impl: @fake) }

    assert_equal 1, @fake.freed_settings.size
    assert_equal 1, @fake.freed_contexts.size
  end

  def test_register_profile_frees_the_context_when_the_profile_is_unknown
    @fake.settings_new_for_profile_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { Hegel::Settings.register_profile("a", profile: "nope", impl: @fake) }

    assert_empty @fake.freed_settings
    assert_equal 1, @fake.freed_contexts.size
  end

  def test_set_default_profile_passes_the_name_and_frees_the_context
    assert_nil Hegel::Settings.set_default_profile("nightly", impl: @fake)
    assert_nil Hegel::Settings.set_default_profile("", impl: @fake)

    assert_equal ["nightly", ""], @fake.set_default_profile_calls
    assert_equal 2, @fake.freed_contexts.size
  end

  def test_set_default_profile_raises_the_engines_error
    @fake.set_default_profile_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    @fake.last_error = "reserved"

    error = assert_raises(Hegel::Error) { Hegel::Settings.set_default_profile("default", impl: @fake) }

    assert_includes error.message, "reserved"
  end

  def test_a_profile_with_print_blob_false_leaves_the_reproduction_line_out_of_the_report
    name = register_profile(print_blob: false)

    assert_no_reproduction_line(failing_report(profile: name))
  end

  def test_a_keyword_beats_the_registered_profile
    name = register_profile(print_blob: false)

    assert_includes failing_report(profile: name, print_blob: true), "reproduce_failure"
  end

  def test_a_profile_derived_from_another_inherits_what_it_does_not_override
    base = register_profile(print_blob: false)
    derived = "hegel-ruby-test-#{SecureRandom.hex(4)}"
    Hegel::Settings.register_profile(derived, profile: base, test_cases: 5)

    assert_no_reproduction_line(failing_report(profile: derived))
  end

  def test_the_default_profile_applies_to_a_run_that_names_none
    name = register_profile(print_blob: false)
    Hegel::Settings.set_default_profile(name)

    assert_no_reproduction_line(failing_report)
  ensure
    Hegel::Settings.set_default_profile("")
  end

  def test_clearing_the_default_profile_restores_the_engine_default
    name = register_profile(print_blob: false)
    Hegel::Settings.set_default_profile(name)
    Hegel::Settings.set_default_profile("")

    assert_includes failing_report, "reproduce_failure"
  ensure
    Hegel::Settings.set_default_profile("")
  end

  def test_an_unknown_profile_raises_the_engines_message
    error = assert_raises(Hegel::Error) do
      Hegel.test(profile: "no-such-profile-#{SecureRandom.hex(4)}", output: StringIO.new) { |_tc| nil }
    end

    assert_includes error.message, "HEGEL_E_INVALID_ARG"
    assert_includes error.message, "no-such-profile"
  end

  def test_registering_the_reserved_name_base_raises_the_engines_message
    error = assert_raises(Hegel::Error) { Hegel::Settings.register_profile("base", print_blob: false) }

    assert_includes error.message, "HEGEL_E_INVALID_ARG"
    assert_includes error.message, "base"
  end

  private

  def register_profile(**keywords)
    name = "hegel-ruby-test-#{SecureRandom.hex(4)}"
    Hegel::Settings.register_profile(name, **keywords)
    name
  end

  def failing_report(**keywords)
    output = StringIO.new
    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 10, output: output, **keywords) { |_tc| raise "boom" }
    end
    output.string
  end

  def assert_no_reproduction_line(report)
    assert_includes report, "Falsified after"
    refute_includes report, "reproduce_failure"
  end
end
