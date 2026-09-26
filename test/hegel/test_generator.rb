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
    fake = span_recording_fake
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |tc| tc.draw(integers.filter { |_| false }) }

    filter_spans = fake.spans.select { |kind,| kind == :filter }
    assert_equal [[:filter, :start], [:filter, :stop, true]] * Hegel::Generator::Filtered::MAX_ATTEMPTS,
      filter_spans
  end

  # #do_draw's ensure block reads +accepted+ before the predicate ever runs
  # when the source draw itself raises. The pre-loop "accepted = false"
  # (not the parser's own implicit nil) is what makes that span record a
  # discard, matching every other attempt this generator never gets to
  # complete. The fake is configured as a failing run (see
  # failing_fake_replaying_the_same_body in test_runner.rb) so the raised
  # exception reaches the caller, which runs +block+ twice -- once live,
  # once on replay -- recording the same discarded span both times.
  def test_filter_discards_the_span_when_the_source_draw_raises
    fake = span_recording_fake
    fake.test_case_count = 1
    fake.run_result_status_value = Hegel::LibHegel::HEGEL_RUN_STATUS_FAILED
    fake.failure_count = 1
    fake.failure_origins = ["origin.rb:1"]
    fake.failure_blobs = ["blob"]

    assert_raises(RuntimeError) do
      Hegel.test(impl: fake) { |tc| tc.draw(RaisingGenerator.new.filter { |_| true }) }
    end

    assert_equal [[:filter, :start], [:filter, :stop, true]] * 2, fake.spans.select { |kind,| kind == :filter }
  end

  # Mapped#do_draw wraps its whole span in HEGEL_LABEL_MAPPED, distinct
  # from Filtered's HEGEL_LABEL_FILTER, so the shrinker can tell a #map
  # transform from a #filter retry.
  def test_map_opens_a_span_labelled_mapped_around_the_source_draw
    fake = span_recording_fake
    fake.test_case_count = 1

    Hegel.test(impl: fake) { |tc| tc.draw(integers.map { |n| n }) }

    assert_equal [[:mapped, :start], [:mapped, :stop, false]], fake.spans.select { |kind,| kind == :mapped }
  end

  private

  # A Fake that records every hegel_start_span / hegel_stop_span call as
  # [:filter, :start], [:filter, :stop, discard], [:mapped, :start], or
  # [:mapped, :stop, discard], keyed off the label so a test can isolate
  # Filtered's spans from Mapped's without reading the raw HEGEL_LABEL_*
  # constant at each assertion site. hegel_stop_span always closes the
  # span #start_span most recently opened (see Hegel::TestCase#stop_span),
  # so a label stack, not the discard argument alone, says which span each
  # stop belongs to.
  def span_recording_fake
    spans = []
    open_labels = []
    fake = Class.new(Hegel::LibHegel::Fake) do
      define_method(:start_span) do |ctx, tc, label|
        name = {Hegel::LibHegel::HEGEL_LABEL_FILTER => :filter, Hegel::LibHegel::HEGEL_LABEL_MAPPED => :mapped}
          .fetch(label, label)
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
