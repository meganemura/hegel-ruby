# frozen_string_literal: true

require "test_helper"
require "hegel/lib_hegel"
require "hegel/lib_hegel/real"
require "support/fake_lib_hegel"

class TestLibHegelGrammar < Minitest::Test
  MARKER = /\A<<EXPLICIT_NUM_\h+>>\z/

  def setup
    @real = Hegel::LibHegel::Real.new
  end

  # Opens a run of one case with the database off, yields the context and
  # that case's handle, then drains and frees the run.
  def with_live_test_case
    Hegel::LibHegel.with_context(@real) do |ctx|
      settings = @real.settings_new(ctx)
      @real.settings_set_test_cases(ctx, settings, 1)
      @real.settings_set_verbosity(ctx, settings, Hegel::LibHegel::HEGEL_VERBOSITY_QUIET)
      @real.settings_set_database(ctx, settings, "")
      run = @real.run_start(ctx, settings)
      @real.settings_free(ctx, settings)
      begin
        while (tc = @real.next_test_case(ctx, run))
          begin
            yield ctx, tc
            @real.mark_complete(ctx, tc, Hegel::LibHegel::HEGEL_STATUS_VALID, nil)
          ensure
            @real.test_case_free(ctx, tc)
          end
        end
      ensure
        @real.run_free(ctx, run)
      end
    end
  end

  # Builds a grammar from +text+ with no imports and yields it, freeing the
  # builder and the grammar afterwards.
  def with_grammar(ctx, text, start: nil, max_size: 0, max_depth: 0, alphabet: nil, names: [])
    builder = @real.grammar_builder_new(ctx, text)
    begin
      grammar = @real.grammar_new(ctx, builder, start, max_size, max_depth, alphabet, names)
    ensure
      @real.grammar_builder_free(ctx, builder)
    end
    begin
      yield grammar
    ensure
      @real.grammar_free(ctx, grammar)
    end
  end

  def test_real_builder_lists_each_import_until_not_found_and_takes_each_file
    with_live_test_case do |ctx, tc|
      builder = @real.grammar_builder_new(ctx, "%import lib.WORD\n%import common.INT\nstart: WORD INT\n")
      begin
        assert_equal "lib.lark", @real.grammar_builder_file(ctx, builder, 0)
        assert_nil @real.grammar_builder_provide(ctx, builder, 0, "WORD: /[a-z]{3}/\n")
        assert_equal "common.lark", @real.grammar_builder_file(ctx, builder, 1)
        assert_nil @real.grammar_builder_provide(ctx, builder, 1, nil)
        assert_nil @real.grammar_builder_file(ctx, builder, 2)

        grammar = @real.grammar_new(ctx, builder, nil, 0, 0, nil, [])
        begin
          assert_match(/\A[a-z]{3}\d+\z/, @real.generate_grammar(ctx, tc, grammar, 0))
        ensure
          @real.grammar_free(ctx, grammar)
        end
      ensure
        @real.grammar_builder_free(ctx, builder)
      end
    end
  end

  # NULL is a missing file, which only a bundled grammar may stand in for;
  # an empty string is a file that exists and defines nothing.
  def test_real_builder_provide_keeps_a_missing_file_apart_from_an_empty_one
    Hegel::LibHegel.with_context(@real) do |ctx|
      builder = @real.grammar_builder_new(ctx, "%import lib.WORD\nstart: WORD\n")
      begin
        missing = assert_raises(Hegel::Error) { @real.grammar_builder_provide(ctx, builder, 0, nil) }
        assert_includes missing.message, "HEGEL_E_INVALID_ARG"

        @real.grammar_builder_provide(ctx, builder, 0, "")
        undefined = assert_raises(Hegel::Error) { @real.grammar_new(ctx, builder, nil, 0, 0, nil, []) }
        assert_includes undefined.message, "WORD"
      ensure
        @real.grammar_builder_free(ctx, builder)
      end
    end
  end

  def test_real_builder_new_sends_the_text_as_utf8
    with_live_test_case do |ctx, tc|
      with_grammar(ctx, "start: \"é\"".encode(Encoding::ISO_8859_1)) do |grammar|
        assert_equal "é", @real.generate_grammar(ctx, tc, grammar, 0)
      end
    end
  end

  def test_real_grammar_new_selects_the_start_rule
    with_live_test_case do |ctx, tc|
      with_grammar(ctx, "a: \"a\"\nb: \"b\"\n", start: "b") do |grammar|
        assert_equal "b", @real.generate_grammar(ctx, tc, grammar, 0)
      end
    end
  end

  def test_real_grammar_new_passes_max_size_and_max_depth_through
    Hegel::LibHegel.with_context(@real) do |ctx|
      size = assert_raises(Hegel::Error) { with_grammar(ctx, "start: \"a\"", max_size: 2**64 - 1) {} }
      assert_includes size.message, "max_size is 18446744073709551615"

      depth = assert_raises(Hegel::Error) { with_grammar(ctx, "start: \"a\"", max_depth: 2**32 - 1) {} }
      assert_includes depth.message, "max_depth is 4294967295"
    end
  end

  def test_real_grammar_new_takes_an_alphabet_handle
    with_live_test_case do |ctx, tc|
      alphabet = @real.string_generator_text(ctx, min_size: 0, max_size: 0, min_codepoint: 97, max_codepoint: 98)
      begin
        with_grammar(ctx, "start: /[a-z]+/", alphabet: alphabet) do |grammar|
          assert_match(/\A[ab]+\z/, @real.generate_grammar(ctx, tc, grammar, 0))
        end
      ensure
        @real.string_generator_free(ctx, alphabet)
      end
    end
  end

  def test_real_grammar_new_reads_each_explicit_name_and_placeholder_names_its_marker
    with_live_test_case do |ctx, tc|
      with_grammar(ctx, "start: NUM WORD\n%declare NUM WORD\n", names: %w[NUM WORD]) do |grammar|
        number = @real.grammar_placeholder(ctx, grammar, "NUM")
        word = @real.grammar_placeholder(ctx, grammar, "WORD")
        assert_match MARKER, number
        assert_match(/\A<<EXPLICIT_WORD_\h+>>\z/, word)
        assert_equal number + word, @real.generate_grammar(ctx, tc, grammar, 0)
      end
    end
  end

  def test_real_grammar_placeholder_raises_for_a_name_that_is_not_explicit
    Hegel::LibHegel.with_context(@real) do |ctx|
      with_grammar(ctx, "start: \"a\"") do |grammar|
        error = assert_raises(Hegel::Error) { @real.grammar_placeholder(ctx, grammar, "NUM") }
        assert_includes error.message, "'NUM' is not an explicit terminal"
      end
    end
  end

  def test_real_generate_grammar_caps_the_draw_at_max_size
    with_live_test_case do |ctx, tc|
      with_grammar(ctx, "start: \"a\"+", max_size: 100) do |grammar|
        assert_operator @real.generate_grammar(ctx, tc, grammar, 3).length, :<=, 3
      end
    end
  end

  def test_real_grammar_frees_are_no_ops_on_nil
    assert_nil @real.grammar_builder_free(nil, nil)
    assert_nil @real.grammar_free(nil, nil)
  end

  def test_real_grammar_calls_raise_on_nil_handles
    Hegel::LibHegel.with_context(@real) do |ctx|
      calls = {
        grammar_builder_file: -> { @real.grammar_builder_file(ctx, nil, 0) },
        grammar_builder_provide: -> { @real.grammar_builder_provide(ctx, nil, 0, "") },
        grammar_new: -> { @real.grammar_new(ctx, nil, nil, 0, 0, nil, []) },
        grammar_placeholder: -> { @real.grammar_placeholder(ctx, nil, "NUM") },
        generate_grammar: -> { @real.generate_grammar(ctx, nil, nil, 0) }
      }

      calls.each do |name, call|
        error = assert_raises(Hegel::Error) { call.call }
        assert_includes error.message, "HEGEL_E_INVALID_HANDLE", "#{name} did not report an invalid handle"
      end
    end
  end

  def test_real_grammar_builder_new_raises_on_a_grammar_that_does_not_parse
    Hegel::LibHegel.with_context(@real) do |ctx|
      error = assert_raises(Hegel::Error) { @real.grammar_builder_new(ctx, "start: ???") }
      assert_includes error.message, "HEGEL_E_INVALID_ARG"
    end
  end

  def test_check_names_not_found
    fake = Hegel::LibHegel::Fake.new
    error = assert_raises(Hegel::Error) do
      Hegel::LibHegel.check!(fake, fake.context_new, Hegel::LibHegel::HEGEL_E_NOT_FOUND)
    end
    assert_includes error.message, "HEGEL_E_NOT_FOUND (-11)"
  end
end
