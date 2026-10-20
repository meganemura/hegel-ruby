# frozen_string_literal: true

require "test_helper"
require "support/fake_lib_hegel"
require "stringio"

# Records, in one list and in call order, every native call a recursive draw
# can make, so a test can assert the exact sequence the engine would see.
class RecursionEventFake < Hegel::LibHegel::Fake
  attr_reader :events

  def initialize
    super
    @events = []
  end

  def start_span(ctx, tc, label)
    @events << [:start, label]
    super
  end

  def stop_span(ctx, tc, discard)
    @events << [:stop, discard]
    super
  end

  def generate_integer(ctx, tc, min_value, max_value)
    @events << :integer
    super
  end

  def new_collection(ctx, tc, min_size, max_size)
    @events << :new_collection
    super
  end

  def collection_more(ctx, tc, collection)
    @events << :more
    super
  end

  def collection_free(ctx, collection)
    @events << :collection_free
    super
  end

  def new_recursion(ctx, tc, max_depth, max_leaves)
    @events << :new_recursion
    super
  end

  def recursion_branch(ctx, tc, recursion, depth)
    @events << [:branch, depth]
    super
  end

  def recursion_leaf(ctx, tc, recursion)
    @events << :leaf
    super
  end

  def recursion_retry(ctx, tc, recursion)
    @events << :retry
    super
  end

  def recursion_finish(ctx, tc, recursion)
    @events << :finish
    super
  end

  def recursion_free(ctx, recursion)
    @events << :free
    super
  end
end

# Forwards to a Fake until armed, then fails on any call that takes a
# test-case handle, so a test can show a call never reached the engine.
class EngineTripwire < BasicObject
  CONTEXT_ONLY = %i[collection_free string_generator_free pool_free state_machine_free recursion_free
    context_last_error].freeze

  def initialize(inner)
    @inner = inner
    @armed = false
  end

  def arm!
    @armed = true
  end

  def method_missing(name, *args, **kwargs, &block)
    ::Kernel.raise ::Minitest::Assertion, "#{name} reached the engine" if @armed && !CONTEXT_ONLY.include?(name)

    @inner.public_send(name, *args, **kwargs, &block)
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end
end

class TestRecursive < Minitest::Test
  include HegelDirectoryGuard
  include Hegel::Syntax::Methods

  RETRY = Hegel::LibHegel::HEGEL_E_RETRY

  def teardown
    refute_new_hegel_directory
  end

  # ---- Hegel::TestCase ----

  def test_a_leaf_within_budget_returns_and_leaves_the_test_case_live
    fake = RecursionEventFake.new
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(3, 5)

    assert_nil tc.recursion_leaf(recursion)
    refute tc.abandoned_by?(recursion)
    tc.generate_integer(0, 1)

    assert_equal [:new_recursion, :leaf, :integer], fake.events
    assert_equal [[3, 5]], fake.new_recursion_calls
  end

  def test_a_leaf_over_budget_abandons_the_attempt_for_its_own_recursion
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [RETRY]
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(1, 1)

    error = assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }

    assert_same recursion, error.recursion
    assert tc.abandoned_by?(recursion)
    refute tc.abandoned_by?(Hegel::TestCase::Recursion.new(Object.new, false))
  end

  def test_an_abandoned_attempt_raises_again_on_every_call_that_takes_the_test_case_handle
    tripwire = EngineTripwire.new(Hegel::LibHegel::Fake.new.tap { |f| f.recursion_leaf_codes = [RETRY] })
    tc = Hegel::TestCase.new(tripwire, Object.new, Object.new)
    recursion = tc.new_recursion(1, 1)
    error = assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }
    tripwire.arm!

    handle_taking_calls(tc, recursion).each do |name, call|
      assert_same error, assert_raises(Hegel::LeafBudgetExceeded, name) { call.call }, name
    end
  end

  def test_an_abandoned_attempt_closes_no_span_and_still_frees
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [RETRY]
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(1, 1)
    assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }

    assert_nil tc.stop_span(discard: false)
    tc.collection_free(Object.new)
    tc.recursion_free(recursion)

    assert_equal [:new_recursion, :leaf, :collection_free, :free], fake.events
    assert recursion.freed
  end

  def test_a_retry_returns_the_test_case_to_the_engine
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [RETRY]
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(1, 1)
    assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }

    assert_nil tc.recursion_retry(recursion)
    refute tc.abandoned_by?(recursion)
    tc.generate_integer(0, 1)
    tc.stop_span(discard: false)

    assert_equal [:new_recursion, :leaf, :retry, :integer, [:stop, false]], fake.events
  end

  def test_a_retry_that_ends_the_test_case_raises_its_verdict_from_then_on
    {Hegel::LibHegel::HEGEL_E_ASSUME => Hegel::AssumeFailed, Hegel::LibHegel::HEGEL_E_STOP_TEST => Hegel::StopTest}
      .each do |code, klass|
        fake = RecursionEventFake.new
        fake.recursion_leaf_codes = [RETRY]
        fake.recursion_retry_codes = [code]
        tc = fake_test_case(fake)
        recursion = tc.new_recursion(1, 1)
        assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }

        verdict = assert_raises(klass) { tc.recursion_retry(recursion) }
        refute tc.abandoned_by?(recursion)
        assert_same verdict, assert_raises(klass) { tc.generate_integer(0, 1) }
        tc.stop_span(discard: false)

        assert_equal [:new_recursion, :leaf, :retry], fake.events
      end
  end

  def test_recursion_branch_and_finish_pass_the_engine_answer_through
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true]
    fake.recursion_finish_codes = [RETRY]
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(1, 1)

    assert_equal true, tc.recursion_branch(recursion, 0)
    assert_equal false, tc.recursion_branch(recursion, 1)
    assert_equal false, tc.recursion_finish(recursion)
    assert_equal true, tc.recursion_finish(recursion)
    assert_equal [:new_recursion, [:branch, 0], [:branch, 1], :finish, :finish], fake.events
  end

  # ---- Hegel::Runner ----

  # A body that swallows the abandoned attempt and draws again gets the
  # attempt back, and the run discards the case rather than reporting it.
  def test_an_abandoned_attempt_reaching_the_run_loop_discards_the_case
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.recursion_leaf_codes = [RETRY]

    Hegel.test(impl: fake, output: StringIO.new) do |tc|
      recursion = tc.new_recursion(1, 1)
      begin
        tc.recursion_leaf(recursion)
      rescue Hegel::LeafBudgetExceeded
        nil
      end
      tc.draw_integer(0, 1)
    end

    assert_equal [Hegel::LibHegel::HEGEL_STATUS_INVALID], fake.marked_statuses
  end

  private

  def fake_test_case(fake)
    Hegel::TestCase.new(fake, fake.context_new, Object.new)
  end

  def handle_taking_calls(tc, recursion)
    {
      draw_integer: -> { tc.draw_integer(0, 1) },
      draw_boolean: -> { tc.draw_boolean },
      draw: -> { tc.draw(integers) },
      generate_integer: -> { tc.generate_integer(0, 1) },
      generate_integer_big: -> { tc.generate_integer_big(0, 2**70) },
      generate_boolean: -> { tc.generate_boolean },
      generate_float: -> {
        tc.generate_float(64, 0.0, 1.0, allow_nan: false, allow_infinity: false, exclude_min: false,
          exclude_max: false, smallest_nonzero_magnitude: 5e-324)
      },
      target: -> { tc.target(1.0) },
      start_span: -> { tc.start_span(1) },
      new_collection: -> { tc.new_collection(0, 1) },
      collection_more: -> { tc.collection_more(Object.new) },
      collection_reject: -> { tc.collection_reject(Object.new) },
      generate_string: -> { tc.generate_string(Object.new) },
      generate_bytes: -> { tc.generate_bytes(0, 1) },
      generate_ipv4: -> { tc.generate_ipv4 },
      generate_ipv6: -> { tc.generate_ipv6 },
      generate_uuid: -> { tc.generate_uuid(4, true) },
      new_pool: -> { tc.new_pool },
      pool_add: -> { tc.pool_add(Object.new) },
      pool_generate: -> { tc.pool_generate(Object.new, false) },
      new_state_machine: -> { tc.new_state_machine(["a"], [], [], 1) },
      state_machine_next_group: -> { tc.state_machine_next_group(Object.new) },
      state_machine_next_rule: -> { tc.state_machine_next_rule(Object.new) },
      state_machine_rule_rejected: -> { tc.state_machine_rule_rejected(Object.new) },
      state_machine_should_check_invariant: -> { tc.state_machine_should_check_invariant(Object.new, 0) },
      generate_date: -> { tc.generate_date([1, 1, 1], [1, 1, 1]) },
      generate_time: -> { tc.generate_time([0, 0, 0, 0], [0, 0, 0, 0]) },
      generate_datetime: -> { tc.generate_datetime([1, 1, 1], [0, 0, 0, 0], [1, 1, 1], [0, 0, 0, 0]) },
      new_recursion: -> { tc.new_recursion(1, 1) },
      recursion_branch: -> { tc.recursion_branch(recursion, 0) },
      recursion_leaf: -> { tc.recursion_leaf(recursion) },
      recursion_finish: -> { tc.recursion_finish(recursion) }
    }
  end
end
