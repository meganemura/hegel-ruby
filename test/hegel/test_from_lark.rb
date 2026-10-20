# frozen_string_literal: true

require "test_helper"
require "support/conformance"
require "support/fake_lib_hegel"
require "pathname"
require "stringio"
require "tmpdir"

class TestFromLark < Minitest::Test
  include HegelDirectoryGuard
  include Hegel::Syntax::Methods
  include Hegel::Conformance

  INT_LIST = "start: INT (\",\" INT)*\n%import common.INT\n"
  FAKE_MARKER = "<<EXPLICIT_NUM_fake>>"
  ATTEMPT = Hegel::Generators::FromLarkGenerator::ATTEMPT_LABEL

  # A generator answering the values it was given, one per draw.
  class QueueGenerator < Hegel::Generator
    def initialize(*values)
      @values = values
    end

    def do_draw(_tc)
      @values.shift
    end
  end

  class RaisingGenerator < Hegel::Generator
    def do_draw(_tc)
      raise "value failed"
    end
  end

  def teardown
    refute_new_hegel_directory
  end

  def int_list?(string)
    string.split(",", -1).all? { |part| part.match?(/\A\d+\z/) }
  end

  def draw_error(generator)
    assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet, output: StringIO.new) { |tc| tc.draw(generator) } }
  end

  def fake_test_case(fake)
    Hegel::TestCase.new(fake, fake.context_new, Object.new)
  end

  # ---- hegel-rust's tests/test_lark.rs ----

  def test_from_lark_generates_strings_of_the_grammar
    assert_all_examples(from_lark(INT_LIST)) { |s| int_list?(s) }
  end

  # Generation alone, where find_any would shrink: shrinking the string down
  # to 2001 characters took up to 25 seconds. Measured against libhegel
  # 0.47.2 over 30 runs, a string past 2000 characters came within the first
  # five cases every time.
  def test_from_lark_generates_large_strings_by_default
    generator = from_lark(INT_LIST)
    found = false
    Hegel.test(test_cases: 100, phases: [:generate], **QUIET_SETTINGS) { |tc| found ||= tc.draw(generator).length > 2000 }

    assert found
  end

  def test_from_lark_shrinks_to_the_smallest_string
    assert_equal "0,0", minimal(from_lark(INT_LIST)) { |s| s.include?(",") }
  end

  def test_from_lark_start_selects_the_rule
    assert_all_examples(from_lark("a: \"a\"+\nb: \"b\"+\n", start: "b")) { |s| s.match?(/\Ab+\z/) }
  end

  def test_from_lark_explicit_supplies_declared_terminals
    generator = from_lark(
      "start: WORD \"!\" NUM\n%declare WORD NUM\n",
      explicit: {"WORD" => from_regex("[a-z]{3}", fullmatch: true), "NUM" => text(alphabet: "0123456789", min_size: 1)}
    )

    assert_all_examples(generator) { |s| s.match?(/\A[a-z]{3}!\d+\z/) }
  end

  def test_from_lark_alphabet_constrains_pattern_terminals
    generator = from_lark("start: /[a-z]+/", alphabet: characters(min_codepoint: "a".ord, max_codepoint: "b".ord))

    assert_all_examples(generator) { |s| s.match?(/\A[ab]+\z/) }
  end

  def test_from_lark_max_size_caps_the_length
    assert_all_examples(from_lark(INT_LIST, max_size: 10)) { |s| int_list?(s) && s.length <= 10 }
  end

  def test_from_lark_max_depth_caps_the_nesting
    generator = from_lark("start: \"(\" start \")\" | \"x\"", max_depth: 3)

    assert_all_examples(generator) { |s| ["x", "(x)", "((x))"].include?(s) }
    find_any(generator) { |s| s == "((x))" }
  end

  def test_from_lark_import_path_resolves_imports
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "lib.lark"), "LETTERS: /[a-z]+/\n")

      assert_all_examples(from_lark("%import lib.LETTERS\nstart: LETTERS\n", import_path: dir)) do |s|
        s.match?(/\A[a-z]+\z/)
      end
    end
  end

  def test_from_lark_import_path_takes_a_pathname
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "lib.lark"), "LETTERS: /[A-Z]+/\n")

      assert_all_examples(from_lark("%import lib.LETTERS\nstart: LETTERS\n", import_path: Pathname(dir))) do |s|
        s.match?(/\A[A-Z]+\z/)
      end
    end
  end

  def test_from_lark_inserts_ignored_terminals
    find_any(from_lark("start: \"a\" \"b\"\n%import common.WS\n%ignore WS\n")) { |s| s.include?(" ") }
  end

  def test_from_lark_draws_inside_collections
    assert_all_examples(arrays(from_lark(INT_LIST, max_size: 20), max_size: 3)) do |v|
      v.length <= 3 && v.all? { |s| int_list?(s) }
    end
  end

  def test_from_lark_labels_distinguish_grammars_and_start_rules
    a = from_lark("start: \"a\"")

    refute_equal a.label, from_lark("start: \"b\"").label
    refute_equal a.label, from_lark("start: \"a\"", start: "other").label
    assert_equal a.label, from_lark("start: \"a\"").label
    assert_equal a.label, from_lark("start: \"a\"", start: "start").label
  end

  def test_from_lark_explicit_overrides_a_pattern_terminal
    generator = from_lark("start: \"a\" NUM\nNUM: /[0-9]+/\n", explicit: {"NUM" => just("xyz")})

    assert_all_examples(generator) { |s| s == "axyz" }
  end

  def test_from_lark_explicit_values_are_spliced_in_as_drawn
    marker = "<<EXPLICIT_NUM_392f5a5e9326>>"
    generator = from_lark("start: \"a\" NUM\n%declare NUM\n", explicit: {"NUM" => just(marker)})

    assert_all_examples(generator) { |s| s == "a#{marker}" }
  end

  # hegel-rust's version of this test and the next keep the default cap.
  # Here each value takes several native calls, about 30 microseconds, and
  # a string of 8192 characters holds a few thousand of them, so a run of
  # either took minutes; the cap keeps the strings short.
  def test_from_lark_explicit_takes_any_string_generator
    generator = from_lark(
      "start: \"[\" NUM (\",\" NUM)* \"]\"\n%declare NUM\n",
      explicit: {"NUM" => integers(min_value: 0, max_value: 255).map(&:to_s)}, max_size: 100
    )

    assert_all_examples(generator) do |s|
      s.delete_prefix("[").delete_suffix("]").split(",", -1).all? { |part| part.match?(/\A\d+\z/) && part.to_i <= 255 }
    end
    find_any(generator) do |s|
      first, *rest = s[1...-1].split(",", -1)
      rest.any? { |part| part != first }
    end
  end

  def test_from_lark_explicit_values_shrink_with_the_grammar
    generator = from_lark(
      "start: NUM (\",\" NUM)*\n%declare NUM\n",
      explicit: {"NUM" => integers(min_value: 0, max_value: (2**32) - 1).map(&:to_s)}, max_size: 100
    )

    assert_equal "0,0", minimal(generator) { |s| s.include?(",") }
  end

  def test_from_lark_explicit_values_get_ignored_text_either_side
    generator = from_lark(
      "start: \"let\" NAME \"=\" NUM\n%declare NAME\nNUM: /[0-9]+/\n%import common.WS\n%ignore WS\n",
      explicit: {"NAME" => text(alphabet: "abc", max_size: 3)}
    )

    assert_all_examples(generator) do |s|
      name, after = s.lstrip.delete_prefix("let").split("=", 2)
      name.match?(/\A\s.*\s\z/m) && name.strip.match?(/\A[abc]*\z/) && after.strip.match?(/\A\d+\z/)
    end
  end

  # The values spliced in count toward max_size like the grammar's own
  # text, and the cap is on the string with them in, not on the markers.
  def test_from_lark_max_size_counts_explicit_values
    generator = from_lark(
      "start: NUM (\",\" NUM)*\n%declare NUM\n",
      explicit: {"NUM" => text(alphabet: "0123456789", min_size: 1, max_size: 6)}, max_size: 12
    )

    assert_all_examples(generator) { |s| s.length <= 12 }
    find_any(generator) { |s| s.length >= 10 }
    find_any(generator) { |s| s.count(",") >= 3 }
  end

  # A string of nothing but explicit values is cut down to fit by drawing
  # fewer of them.
  def test_from_lark_fits_a_string_of_explicit_values_alone
    generator = from_lark(
      "start: NUM+\n%declare NUM\n", explicit: {"NUM" => text(alphabet: "0123456789", min_size: 4, max_size: 4)},
      max_size: 20
    )

    assert_all_examples(generator) { |s| s.length <= 20 && (s.length % 4).zero? }
    find_any(generator) { |s| s.length == 20 }
  end

  def test_from_lark_explicit_values_go_beside_text_like_a_marker
    generator = from_lark(
      "start: \"<\" NUM \">\" \"<<\"\n%declare NUM\n",
      explicit: {"NUM" => text(alphabet: "0123456789", min_size: 1, max_size: 3)}
    )

    assert_all_examples(generator) { |s| s.match?(/\A<\d+><<\z/) }
  end

  # A string whose values cannot fit under max_size however little the
  # grammar's own text takes is rejected, as a failed filter is.
  def test_from_lark_rejects_a_string_whose_explicit_values_cannot_fit
    error = draw_error(from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => text(min_size: 20)}, max_size: 10))

    assert_includes error.message, "FilterTooMuch"
  end

  # A Symbol and a String are the two ways a Ruby Hash names one terminal
  # twice.
  def test_from_lark_rejects_a_terminal_given_two_generators
    error = draw_error(from_lark("start: NUM\n%declare NUM\n", explicit: {:NUM => text, "NUM" => text}))

    assert_includes error.message, "from_lark: explicit terminal 'NUM' is given more than one generator"
  end

  def test_from_lark_labels_include_the_explicit_generators
    grammar = "start: NUM\n%declare NUM\n"
    a = from_lark(grammar, explicit: {"NUM" => text})

    refute_equal a.label, from_lark(grammar, explicit: {"NUM" => from_regex("[0-9]+")}).label
    refute_equal a.label, from_lark(grammar).label
    refute_equal a.label, from_lark(grammar, explicit: {"NAME" => text}).label
    assert_equal a.label, from_lark(grammar, explicit: {NUM: text}).label
  end

  # ---- options this binding adds checks or reads for ----

  def test_from_lark_explicit_takes_symbol_keys
    assert_all_examples(from_lark("start: \"a\" NUM\n%declare NUM\n", explicit: {NUM: just("1")})) { |s| s == "a1" }
  end

  def test_from_lark_import_path_falls_back_to_a_bundled_grammar_when_the_file_is_missing
    Dir.mktmpdir do |dir|
      assert_all_examples(from_lark(INT_LIST, import_path: dir, max_size: 20)) { |s| int_list?(s) }
    end
  end

  def test_from_lark_import_path_that_is_a_file_falls_back_to_a_bundled_grammar
    Dir.mktmpdir do |dir|
      file = File.join(dir, "grammar")
      File.write(file, "")

      assert_all_examples(from_lark(INT_LIST, import_path: file, max_size: 20)) { |s| int_list?(s) }
    end
  end

  def test_from_lark_import_that_cannot_be_read_raises_at_draw_time
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "lib.lark"))

      error = draw_error(from_lark("%import lib.WORD\nstart: WORD\n", import_path: dir))

      assert_includes error.message, "from_lark: Could not read grammar `#{File.join(dir, "lib.lark")}`: Is a directory"
    end
  end

  def test_from_lark_import_that_is_not_utf8_raises_at_draw_time
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "lib.lark"), "WORD: \"\xFF\"\n".b)

      error = draw_error(from_lark("%import lib.WORD\nstart: WORD\n", import_path: dir))

      assert_includes error.message,
        "from_lark: Could not read grammar `#{File.join(dir, "lib.lark")}`: stream did not contain valid UTF-8"
    end
  end

  def test_from_lark_alphabet_options_are_checked_under_its_own_name
    error = draw_error(from_lark("start: /[a-z]+/", alphabet: characters(codec: "not-a-real-codec")))

    assert_includes error.message, "from_lark: invalid codec: not-a-real-codec"
  end

  def test_from_lark_max_size_and_max_depth_too_wide_for_the_engine_get_its_own_message
    size = draw_error(from_lark("start: \"a\"", max_size: 2**70))
    depth = draw_error(from_lark("start: \"a\"", max_depth: 2**40))

    assert_includes size.message, "max_size is 18446744073709551615 but may be at most 1048576"
    assert_includes depth.message, "max_depth is 4294967295 but may be at most 500"
  end

  def test_from_lark_a_grammar_the_engine_rejects_raises_at_draw_time
    assert_includes draw_error(from_lark("start: ???")).message, "HEGEL_E_INVALID_ARG"
  end

  def test_from_lark_a_frozen_generator_draws
    generator = from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => just("7")}).freeze

    assert_all_examples(generator) { |s| s == "7" }
  end

  # ---- validation ----

  def test_from_lark_invalid_options_do_not_raise_until_draw_time
    generator = from_lark(:grammar, start: 1, explicit: [], alphabet: "ab", max_size: 0, max_depth: 0, import_path: 5)

    assert_kind_of Hegel::Generator, generator
    assert_raises(Hegel::Error) { Hegel.test(verbosity: :quiet) { |tc| tc.draw(generator) } }
  end

  def test_from_lark_takes_a_max_size_and_max_depth_of_one
    assert_all_examples(from_lark("start: \"a\"", max_size: 1, max_depth: 1)) { |s| s == "a" }
  end

  def test_from_lark_validation_messages
    grammar = "start: NUM\n%declare NUM\n"
    {
      from_lark(:start) => "from_lark: grammar must be a String, not a Symbol",
      from_lark(grammar, start: :start) => "from_lark: start must be a String, not a Symbol",
      from_lark(grammar, max_size: 0) => "from_lark: max_size must be at least 1",
      from_lark(grammar, max_depth: 0) => "from_lark: max_depth must be at least 1",
      from_lark(grammar, explicit: [["NUM", text]]) => "from_lark: explicit must be a Hash, not a Array",
      from_lark(grammar, explicit: {1 => text}) =>
        "from_lark: an explicit terminal name must be a String or a Symbol, not a Integer",
      from_lark(grammar, explicit: {"NUM" => "1"}) => "from_lark: explicit terminal 'NUM' must be given a generator, not a String",
      from_lark(grammar, explicit: {"NUM" => text}, alphabet: "0123") =>
        "from_lark: alphabet must be a characters generator, not a String",
      from_lark(grammar, explicit: {"NUM" => text}, import_path: 5) =>
        "from_lark: import_path must be a String or a Pathname, not a Integer",
      from_lark(grammar, explicit: {"NUM" => integers}) => "from_lark: explicit terminal 'NUM' drew a Integer, not a String"
    }.each do |generator, message|
      assert_includes draw_error(generator).message, message
    end
  end

  # ---- compiling once a run, against the Fake ----

  def test_a_run_compiles_once_even_for_a_generator_built_inside_the_body
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 4
    outer = from_lark("start: NUM\n%declare NUM\n", explicit: {NUM: just("1")})

    Hegel.test(impl: fake) do |tc|
      tc.draw(outer)
      tc.draw(from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => just("2")}))
    end

    assert_equal 1, fake.grammar_new_calls.size
    assert_equal [[:grammar_free, fake.freed_grammars.first], [:context_free]], fake.events.last(2)
    assert_equal 1, fake.freed_grammars.size
  end

  def test_one_generator_drawn_in_two_runs_compiles_in_each
    generator = from_lark("start: \"a\"")
    fakes = Array.new(2) { Hegel::LibHegel::Fake.new.tap { |fake| fake.test_case_count = 2 } }

    fakes.each { |fake| Hegel.test(impl: fake) { |tc| tc.draw(generator) } }

    fakes.each do |fake|
      assert_equal 1, fake.grammar_new_calls.size
      assert_equal 1, fake.freed_grammars.size
    end
  end

  def test_a_body_that_raises_still_frees_the_grammar
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, output: StringIO.new) do |tc|
        tc.draw(from_lark("start: \"a\""))
        raise "boom"
      end
    end

    assert_equal [[:grammar_free, fake.freed_grammars.first], [:context_free]], fake.events.last(2)
  end

  # Generators differing in one compiled option each compile their own
  # grammar; ones equal by value share one.
  def test_the_cache_key_holds_every_option_the_compilation_reads
    grammar = "start: NUM\n%declare NUM\n"
    base = {explicit: {"NUM" => just("1")}}
    variants = [
      {grammar: "start: NUM \"!\"\n%declare NUM\n"}, {start: "start"}, {max_size: 100}, {max_depth: 50},
      {alphabet: characters(max_codepoint: 127)}, {explicit: {"NUM" => just("1"), "WORD" => just("w")}},
      {import_path: "/nonexistent"}
    ]

    variants.each do |variant|
      fake = Hegel::LibHegel::Fake.new
      fake.test_case_count = 1
      options = base.merge(variant)
      text = options.delete(:grammar) || grammar
      Hegel.test(impl: fake) do |tc|
        tc.draw(from_lark(grammar, **base))
        tc.draw(from_lark(text, **options))
      end

      assert_equal 2, fake.grammar_new_calls.size, "for #{variant.keys.first}"
    end

    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    Hegel.test(impl: fake) do |tc|
      tc.draw(from_lark(+grammar, explicit: {"NUM" => just("1")}, import_path: "/x", alphabet: characters))
      tc.draw(from_lark(+grammar, explicit: {NUM: just("2")}, import_path: Pathname("/x"), alphabet: characters))
    end
    assert_equal 1, fake.grammar_new_calls.size
  end

  def test_a_test_case_without_a_cache_compiles_and_frees_on_each_draw
    fake = Hegel::LibHegel::Fake.new
    tc = fake_test_case(fake)
    generator = from_lark("start: \"a\"")

    2.times { generator.do_draw(tc) }

    assert_equal 2, fake.grammar_new_calls.size
    assert_equal 2, fake.freed_grammars.uniq.size
  end

  def test_compile_passes_each_option_and_provides_each_import
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "lib.lark"), "WORD: /[a-z]+/\n")
      fake = Hegel::LibHegel::Fake.new
      fake.grammar_builder_files = ["lib.lark", "common.lark"]
      generator = from_lark(
        "%import lib.WORD\nstart: WORD NUM\n", start: "start", max_size: 40, max_depth: 7,
        explicit: {NUM: just("1")}, alphabet: characters(max_codepoint: 90), import_path: dir
      )

      generator.do_draw(fake_test_case(fake))

      builder = fake.freed_grammar_builders.fetch(0)
      ((text_options, alphabet),) = fake.string_generator_text_calls
      assert_equal ["%import lib.WORD\nstart: WORD NUM\n"], fake.grammar_builder_texts
      assert_equal [[builder, 0, "WORD: /[a-z]+/\n"], [builder, 1, nil]], fake.grammar_builder_provides
      assert_equal Encoding::UTF_8, fake.grammar_builder_provides.dig(0, 2).encoding
      assert_equal [{builder: builder, start: "start", max_size: 40, max_depth: 7, alphabet: alphabet, names: ["NUM"]}],
        fake.grammar_new_calls
      assert_equal({min_size: 0, max_size: 0, max_codepoint: 90}, text_options.slice(:min_size, :max_size, :max_codepoint))
      assert_equal [alphabet], fake.freed_string_generators
    end
  end

  def test_compile_without_an_import_path_reports_every_file_missing_and_takes_the_default_caps
    fake = Hegel::LibHegel::Fake.new
    fake.grammar_builder_files = ["common.lark"]

    from_lark(INT_LIST).do_draw(fake_test_case(fake))

    builder = fake.freed_grammar_builders.fetch(0)
    assert_equal [[builder, 0, nil]], fake.grammar_builder_provides
    assert_equal [{builder: builder, start: nil, max_size: 8192, max_depth: 0, alphabet: nil, names: []}],
      fake.grammar_new_calls
    assert_empty fake.string_generator_text_calls
  end

  def test_compile_frees_the_builder_when_providing_a_file_raises
    fake = Hegel::LibHegel::Fake.new
    fake.grammar_builder_files = ["lib.lark"]
    fake.grammar_builder_provide_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { from_lark("start: \"a\"").do_draw(fake_test_case(fake)) }

    assert_equal 1, fake.freed_grammar_builders.size
    assert_empty fake.grammar_new_calls
  end

  def test_compile_frees_the_builder_and_the_alphabet_when_grammar_new_raises
    fake = Hegel::LibHegel::Fake.new
    fake.grammar_new_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { from_lark("start: \"a\"", alphabet: characters).do_draw(fake_test_case(fake)) }

    assert_equal 1, fake.freed_grammar_builders.size
    assert_equal 1, fake.freed_string_generators.size
    assert_empty fake.freed_grammars
  end

  def test_compile_frees_the_grammar_when_a_placeholder_raises_and_caches_nothing
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 2
    fake.grammar_placeholder_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1

    assert_raises(Hegel::Error) do
      Hegel.test(impl: fake, output: StringIO.new) do |tc|
        tc.draw(from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => just("1")}))
      end
    end

    assert_equal 2, fake.grammar_new_calls.size
    assert_equal 2, fake.freed_grammars.size
  end

  # ---- spans and budgets, against the Fake ----

  def test_a_grammar_without_explicit_terminals_draws_once_under_the_grammars_own_cap_with_no_span
    fake = Hegel::LibHegel::Fake.new
    fake.generate_grammar_values = ["abc"]

    assert_equal "abc", from_lark("start: \"abc\"", max_size: 50).do_draw(fake_test_case(fake))

    assert_equal [0], fake.generate_grammar_max_sizes
    assert_empty(fake.events.select { |event| event.first.end_with?("span") })
  end

  def test_an_oversize_string_is_drawn_again_under_a_smaller_budget_in_a_discarded_span
    fake = Hegel::LibHegel::Fake.new
    fake.generate_grammar_values = ["#{FAKE_MARKER},#{FAKE_MARKER},", "#{FAKE_MARKER}!"]
    value = just("123456")
    generator = from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => value}, max_size: 12)

    assert_equal "123456!", generator.do_draw(fake_test_case(fake))

    assert_equal [12, 3], fake.generate_grammar_max_sizes
    value_span = [[:start_span, value.label], [:stop_span, false]]
    assert_equal(
      [
        [:start_span, generator.label], [:start_span, ATTEMPT], [:generate_grammar, 12], *value_span, *value_span,
        [:stop_span, true], [:start_span, ATTEMPT], [:generate_grammar, 3], *value_span, [:stop_span, false],
        [:stop_span, false]
      ],
      fake.events.reject { |event| %i[grammar_new grammar_free].include?(event.first) }
    )
  end

  # Each budget is the cap scaled by the grammar's share of the string, at
  # most one below the last and at least 1.
  def test_three_oversize_strings_reject_the_case
    fake = Hegel::LibHegel::Fake.new
    fake.generate_grammar_values = ["#{"a" * 13}#{FAKE_MARKER}", FAKE_MARKER, FAKE_MARKER]
    generator = from_lark(
      "start: NUM\n%declare NUM\n", explicit: {"NUM" => QueueGenerator.new("", "x" * 13, "x" * 13)}, max_size: 12
    )

    assert_raises(Hegel::AssumeFailed) { generator.do_draw(fake_test_case(fake)) }

    assert_equal [12, 11, 1], fake.generate_grammar_max_sizes
    stops = fake.events.select { |event| event.first == :stop_span }.map(&:last)
    assert_equal [false, true, false, true, false, true, false], stops
  end

  def test_a_value_that_raises_closes_every_span_kept
    fake = Hegel::LibHegel::Fake.new
    fake.generate_grammar_values = [FAKE_MARKER]
    explicit = RaisingGenerator.new
    generator = from_lark("start: NUM\n%declare NUM\n", explicit: {"NUM" => explicit})

    assert_raises(RuntimeError) { generator.do_draw(fake_test_case(fake)) }

    assert_equal(
      [
        [:start_span, generator.label], [:start_span, ATTEMPT], [:start_span, explicit.label],
        [:stop_span, false], [:stop_span, false], [:stop_span, false]
      ],
      fake.events.select { |event| event.first.end_with?("span") }
    )
  end

  # The first marker in the string decides; a value spliced in is not read
  # again for markers.
  def test_markers_are_replaced_leftmost_first_without_reading_a_value_again
    fake = Hegel::LibHegel::Fake.new
    word_marker = "<<EXPLICIT_WORD_fake>>"
    fake.generate_grammar_values = ["<<#{word_marker}#{FAKE_MARKER}<<"]
    generator = from_lark(
      "start: WORD NUM\n%declare WORD NUM\n", explicit: {"NUM" => just(word_marker), "WORD" => just("w")}
    )

    assert_equal "<<w#{word_marker}<<", generator.do_draw(fake_test_case(fake))
  end
end
