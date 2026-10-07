# frozen_string_literal: true

require "test_helper"
require "support/fake_lib_hegel"

class TestGenerator < Minitest::Test
  include HegelDirectoryGuard
  include Hegel::Syntax::Methods

  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step regressed (see TestRunner#teardown); every real-engine test in
  # this class must leave none.
  def teardown
    refute_new_hegel_directory
  end

  def test_do_draw_raises_not_implemented_for_a_generator_that_does_not_override_it
    generator = Hegel::Generator.new

    assert_raises(NotImplementedError) { generator.do_draw(nil) }
  end

  # #map and #filter come from Hegel::Generator alone, so a generator class
  # that implements #do_draw without that parent would draw values yet raise
  # NoMethodError on #map. The tests of each generator draw through
  # Hegel::TestCase#draw, which calls only #do_draw, so none of them would
  # notice. This one checks every such class in the library at once.
  def test_every_class_that_implements_do_draw_is_a_generator
    drawing_classes = ObjectSpace.each_object(Class).select do |klass|
      klass.name&.start_with?("Hegel::") && klass.method_defined?(:do_draw, false)
    end

    assert_includes drawing_classes, Hegel::Generators::BooleanGenerator
    drawing_classes.each do |klass|
      assert_operator klass, :<=, Hegel::Generator, "#{klass} implements #do_draw but is not a Hegel::Generator"
    end
  end

  def test_map_transforms_every_drawn_value_against_the_real_engine
    result = Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
      v = tc.draw(integers(min_value: 0, max_value: 100).map { |n| n * 2 })
      raise "not even: #{v}" unless v.even?
    end

    assert_nil result
  end

  def test_filter_only_yields_values_that_satisfy_the_predicate_against_the_real_engine
    result = Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
      v = tc.draw(integers(min_value: 0, max_value: 100).filter(&:even?))
      raise "not even: #{v}" unless v.even?
    end

    assert_nil result
  end

  # A predicate that never holds must not hang the run: libhegel's own
  # health check aborts it (see Hegel::Generator::Filtered), surfaced here
  # as Hegel::Error the same way any other run-level failure is.
  def test_filter_with_an_impossible_predicate_does_not_loop_forever
    assert_raises(Hegel::Error) do
      Hegel.test(verbosity: :quiet) do |tc|
        tc.draw(integers.filter { |_| false })
      end
    end
  end

  # A generator whose #do_draw always raises, so a test can force
  # Filtered#do_draw's ensure block to run with the predicate never called
  # -- the one path where the pre-loop "accepted = false" matters, since
  # nothing later in the same iteration assigns it.
  class RaisingGenerator < Hegel::Generator
    def do_draw(_tc)
      raise "boom"
    end
  end

  # Every attempt gets its own span, each closed with the outcome the
  # predicate reached for that attempt -- Hegel::Generator::Filtered's own
  # comment on retrying "each attempt in its own span". A predicate that
  # never holds runs MAX_ATTEMPTS spans, every one discarded. Against this
  # Fake (no health check), the discarded case just ends the run normally,
  # so only the recorded spans matter here.
  def test_filter_opens_and_discards_one_span_per_rejected_attempt
    generator = integers.filter { |_| false }
    fake = span_recording_fake(generator.label => :filter)
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |tc| tc.draw(generator) }

    filter_spans = fake.spans.select { |kind,| kind == :filter }
    assert_equal [[:filter, :start], [:filter, :stop, true]] * Hegel::Generator::Filtered::MAX_ATTEMPTS,
      filter_spans
  end

  # #do_draw's ensure block reads +accepted+ before the predicate ever runs
  # when the source draw itself raises. The pre-loop "accepted = false"
  # (not the parser's own implicit nil) is what makes that span record a
  # discard, matching every other attempt this generator never gets to
  # complete. The fake is configured as a failing run (see failing_fake in
  # test_runner.rb) so the raised exception reaches the caller.
  def test_filter_discards_the_span_when_the_source_draw_raises
    generator = RaisingGenerator.new.filter { |_| true }
    fake = span_recording_fake(generator.label => :filter)
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    fake.failure_blobs = ["blob"]

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake, output: StringIO.new) { |tc| tc.draw(generator) }
    end

    assert_equal [[:filter, :start], [:filter, :stop, true]], fake.spans.select { |kind,| kind == :filter }
  end

  # Mapped#do_draw wraps its whole draw in one span with its own label.
  def test_map_opens_a_span_with_its_own_label_around_the_source_draw
    generator = integers.map { |n| n }
    fake = span_recording_fake(generator.label => :mapped)
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |tc| tc.draw(generator) }

    assert_equal [[:mapped, :start], [:mapped, :stop, false]], fake.spans.select { |kind,| kind == :mapped }
  end

  # The engine reads two spans with one label as draws of one generator.
  # A label therefore names the generator's shape: map of integers and
  # filter of integers differ, map of integers and map of text differ, and
  # two separately built maps of integers agree.
  def test_a_label_names_the_combinator_and_its_source
    assert_equal integers.map { |n| n }.label, integers.map { |n| n + 1 }.label
    refute_equal integers.map { |n| n }.label, integers.filter { |_| true }.label
    refute_equal integers.map { |n| n }.label, text.map { |s| s }.label
    refute_equal integers.label, integers.map { |n| n }.label
  end

  private

  # A Fake that records every hegel_start_span / hegel_stop_span call as
  # [name, :start] or [name, :stop, discard], where +names+ maps a label to
  # the name a test asserts on. hegel_stop_span always closes the span
  # #start_span most recently opened (see Hegel::TestCase#stop_span), so a
  # label stack, not the discard argument alone, says which span each stop
  # belongs to.
  def span_recording_fake(names)
    spans = []
    open_labels = []
    fake = Class.new(Hegel::LibHegel::Fake) do
      define_method(:start_span) do |ctx, tc, label|
        name = names.fetch(label, label)
        open_labels << name
        spans << [name, :start]
        super(ctx, tc, label)
      end

      define_method(:stop_span) do |ctx, tc, discard|
        spans << [open_labels.pop, :stop, discard]
        super(ctx, tc, discard)
      end
    end.new
    fake.define_singleton_method(:spans) { spans }
    fake
  end
end
