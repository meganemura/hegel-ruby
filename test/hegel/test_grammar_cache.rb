# frozen_string_literal: true

require "test_helper"
require "support/fake_lib_hegel"
require "stringio"

class TestGrammarCache < Minitest::Test
  include HegelDirectoryGuard

  def teardown
    refute_new_hegel_directory
  end

  def compiled(grammar = Object.new)
    Hegel::GrammarCache::Compiled.new(grammar: grammar, markers: [])
  end

  # A body that compiles one grammar under +key+ through the test case.
  def draw_grammar(tc, key = :key)
    build = -> { compiled(tc.grammar_new(nil, nil, 0, 0, nil, [])) }
    tc.with_grammar(key, build) { |entry| entry }
  end

  def test_fetch_builds_once_per_key
    cache = Hegel::GrammarCache.new
    builds = 0
    first = cache.fetch(:a) { builds += 1 }
    again = cache.fetch(:a) { builds += 1 }
    other = cache.fetch(:b) { builds += 1 }

    assert_equal [1, 1, 2], [first, again, other]
  end

  def test_fetch_stores_nothing_when_the_build_raises
    cache = Hegel::GrammarCache.new

    assert_raises(RuntimeError) { cache.fetch(:a) { raise "compile failed" } }

    assert_equal :built, cache.fetch(:a) { :built }
  end

  def test_free_all_frees_each_grammar_once_and_empties_the_cache
    fake = Hegel::LibHegel::Fake.new
    cache = Hegel::GrammarCache.new
    entries = [cache.fetch(:a) { compiled }, cache.fetch(:b) { compiled }]

    cache.free_all(fake, :ctx)
    cache.free_all(fake, :ctx)

    assert_equal entries.map(&:grammar), fake.freed_grammars
  end

  def test_free_all_frees_the_rest_after_a_free_raises_and_raises_the_first_error
    freed = []
    impl = Object.new
    impl.define_singleton_method(:grammar_free) do |_ctx, grammar|
      freed << grammar
      raise Hegel::Error, "free #{grammar} failed" unless grammar == :c
    end
    cache = Hegel::GrammarCache.new
    %i[a b c].each { |name| cache.fetch(name) { compiled(name) } }

    error = assert_raises(Hegel::Error) { cache.free_all(impl, :ctx) }

    assert_equal "free a failed", error.message
    assert_equal %i[a b c], freed
    assert_equal :new, cache.fetch(:a) { :new }
  end

  def test_a_run_compiles_once_across_cases_and_frees_before_the_context
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 5
    seen = []

    Hegel.test(impl: fake) { |tc| seen << draw_grammar(tc) }

    assert_equal 1, fake.grammar_new_calls.size
    assert_equal 1, seen.uniq.size
    assert_equal [[:grammar_free, seen.first.grammar], [:context_free]], fake.events.last(2)
    assert_equal [seen.first.grammar], fake.freed_grammars
  end

  def test_each_run_compiles_its_own_grammar
    fakes = Array.new(2) { Hegel::LibHegel::Fake.new.tap { |fake| fake.test_case_count = 1 } }

    seen = fakes.map do |fake|
      entry = nil
      Hegel.test(impl: fake) { |tc| entry = draw_grammar(tc) }
      entry
    end

    fakes.zip(seen).each do |fake, entry|
      assert_equal 1, fake.grammar_new_calls.size
      assert_equal [entry.grammar], fake.freed_grammars
    end
  end

  def test_a_failing_run_still_frees_its_grammars
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, output: StringIO.new) do |tc|
        draw_grammar(tc)
        raise "boom"
      end
    end

    assert_equal 1, fake.freed_grammars.size
    assert_equal [:context_free], fake.events.last
  end

  def test_reproduce_failure_frees_its_grammars
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, reproduce_failure: "blob", output: StringIO.new) do |tc|
        draw_grammar(tc)
        raise "boom"
      end
    end

    assert_equal 1, fake.freed_grammars.size
  end

  def test_a_test_case_without_a_cache_compiles_and_frees_on_every_draw
    fake = Hegel::LibHegel::Fake.new
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

    first = draw_grammar(tc)
    second = draw_grammar(tc)

    assert_equal [first.grammar, second.grammar], fake.freed_grammars
    refute_same first.grammar, second.grammar
  end

  def test_a_test_case_without_a_cache_frees_the_grammar_when_the_block_raises
    fake = Hegel::LibHegel::Fake.new
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)
    entry = compiled

    assert_raises(RuntimeError) { tc.with_grammar(:key, -> { entry }) { raise "draw failed" } }

    assert_equal [entry.grammar], fake.freed_grammars
  end

  def test_grammar_calls_delegate_to_impl
    fake = Hegel::LibHegel::Fake.new
    fake.grammar_builder_files = ["lib.lark"]
    fake.generate_grammar_values = ["drawn"]
    tc = Hegel::TestCase.new(fake, fake.context_new, Object.new)

    builder = tc.grammar_builder_new("start: \"a\"")
    assert_equal "lib.lark", tc.grammar_builder_file(builder, 0)
    assert_nil tc.grammar_builder_file(builder, 1)
    tc.grammar_builder_provide(builder, 0, "text")
    grammar = tc.grammar_new(builder, "s", 9, 3, :alphabet, ["NUM"])
    tc.grammar_builder_free(builder)

    assert_equal "<<EXPLICIT_NUM_fake>>", tc.grammar_placeholder(grammar, "NUM")
    assert_equal "drawn", tc.generate_grammar(grammar, 7)
    tc.grammar_free(grammar)

    assert_equal ["start: \"a\""], fake.grammar_builder_texts
    assert_equal [[builder, 0, "text"]], fake.grammar_builder_provides
    assert_equal [{builder: builder, start: "s", max_size: 9, max_depth: 3, alphabet: :alphabet, names: ["NUM"]}],
      fake.grammar_new_calls
    assert_equal [7], fake.generate_grammar_max_sizes
    assert_equal [builder], fake.freed_grammar_builders
    assert_equal [grammar], fake.freed_grammars
  end
end
