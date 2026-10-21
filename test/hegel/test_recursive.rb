# frozen_string_literal: true

require "test_helper"
require "support/fake_lib_hegel"
require "stringio"

# Records, in one list and in call order, every native call a recursive draw
# can make, so a test can assert the exact sequence the engine would see.
class RecursionEventFake < Hegel::LibHegel::Fake
  attr_reader :calls

  def initialize
    super
    @calls = []
  end

  def start_span(ctx, tc, label)
    @calls << [:start, label]
    super
  end

  def stop_span(ctx, tc, discard)
    @calls << [:stop, discard]
    super
  end

  def generate_integer(ctx, tc, min_value, max_value)
    @calls << :integer
    super
  end

  def new_collection(ctx, tc, min_size, max_size)
    @calls << :new_collection
    super
  end

  def collection_more(ctx, tc, collection)
    @calls << :more
    super
  end

  def collection_free(ctx, collection)
    @calls << :collection_free
    super
  end

  def new_recursion(ctx, tc, max_depth, max_leaves)
    @calls << :new_recursion
    super
  end

  def recursion_branch(ctx, tc, recursion, depth)
    @calls << [:branch, depth]
    super
  end

  def recursion_leaf(ctx, tc, recursion)
    @calls << :leaf
    super
  end

  def recursion_retry(ctx, tc, recursion)
    @calls << :retry
    super
  end

  def recursion_finish(ctx, tc, recursion)
    @calls << :finish
    super
  end

  def recursion_free(ctx, recursion)
    @calls << :free
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

    assert_equal [:new_recursion, :leaf, :integer], fake.calls
    assert_equal [[3, 5]], fake.new_recursion_calls
  end

  def test_a_leaf_over_budget_abandons_the_attempt_for_its_own_recursion
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [RETRY]
    tc = fake_test_case(fake)
    recursion = tc.new_recursion(1, 1)

    error = assert_raises(Hegel::LeafBudgetExceeded) { tc.recursion_leaf(recursion) }

    assert_same recursion, error.recursion
    assert_equal "hegel: a recursive draw outgrew its leaf budget; the attempt is retried", error.message
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

    assert_equal [:new_recursion, :leaf, :collection_free, :free], fake.calls
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

    assert_equal [:new_recursion, :leaf, :retry, :integer, [:stop, false]], fake.calls
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

        assert_equal [:new_recursion, :leaf, :retry], fake.calls
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
    assert_equal [:new_recursion, [:branch, 0], [:branch, 1], :finish, :finish], fake.calls
  end

  # ---- RecursiveGenerator against the Fake ----

  def test_a_leaf_draws_inside_the_recursive_span
    fake = RecursionEventFake.new
    generator = recursive(integers) { |subtrees| arrays(subtrees) }

    assert_equal 0, generator.do_draw(fake_test_case(fake))
    assert_equal [[:start, generator.label], :new_recursion, [:branch, 0], :leaf, :integer, :finish, :free,
      [:stop, false]], fake.calls
  end

  # Every subtree span carries the recursive generator's own label.
  def test_a_branch_draws_its_subtrees_at_the_next_depth_under_the_shared_label
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true]
    fake.collection_more_count = 1
    generator = recursive(integers) { |subtrees| arrays(subtrees) }
    array_label = arrays(generator).label

    assert_equal [0], generator.do_draw(fake_test_case(fake))
    assert_equal [
      [:start, generator.label], :new_recursion, [:branch, 0],
      [:start, array_label], :new_collection, :more,
      [:start, generator.label], [:start, generator.label], [:branch, 1], :leaf, :integer, [:stop, false], [:stop, false],
      :more, :collection_free, [:stop, false],
      :finish, :free, [:stop, false]
    ], fake.calls
  end

  def test_the_block_is_called_afresh_for_each_branch
    fake = Hegel::LibHegel::Fake.new
    fake.recursion_branch_values = [true, true]
    fake.collection_more_count = 1
    calls = 0
    generator = recursive(integers) do |subtrees|
      calls += 1
      arrays(subtrees)
    end

    assert_equal [[]], generator.do_draw(fake_test_case(fake))
    assert_equal 2, calls
  end

  # Between the over-budget leaf and the retry, the engine sees no span
  # close, so the retry discards every span the attempt opened; the
  # collection opened inside the attempt is still freed.
  def test_a_leaf_over_budget_unwinds_without_closing_spans_and_retries_from_the_root
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true]
    fake.collection_more_count = 1
    fake.recursion_leaf_codes = [RETRY]
    generator = recursive(integers) { |subtrees| arrays(subtrees) }
    array_label = arrays(generator).label

    assert_equal 0, generator.do_draw(fake_test_case(fake))
    assert_equal [
      [:start, generator.label], :new_recursion, [:branch, 0],
      [:start, array_label], :new_collection, :more, [:start, generator.label], [:start, generator.label],
      [:branch, 1], :leaf, :collection_free, :retry,
      [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false]
    ], fake.calls
  end

  def test_a_finished_attempt_the_engine_discards_starts_again_from_the_root_without_a_retry
    fake = RecursionEventFake.new
    fake.recursion_finish_codes = [RETRY]
    generator = recursive(integers) { |subtrees| arrays(subtrees) }

    generator.do_draw(fake_test_case(fake))
    assert_equal [[:start, generator.label], :new_recursion, [:branch, 0], :leaf, :integer, :finish,
      [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false]], fake.calls
  end

  def test_a_retry_out_of_attempts_discards_the_case_and_later_draws_never_reach_the_engine
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [RETRY]
    fake.recursion_retry_codes = [Hegel::LibHegel::HEGEL_E_ASSUME]
    tc = fake_test_case(fake)
    generator = recursive(integers) { |subtrees| arrays(subtrees) }

    verdict = assert_raises(Hegel::AssumeFailed) { generator.do_draw(tc) }
    assert_same verdict, assert_raises(Hegel::AssumeFailed) { tc.draw(integers) }
    assert_equal [[:start, generator.label], :new_recursion, [:branch, 0], :leaf, :retry, :free], fake.calls
  end

  def test_a_stop_test_from_a_leaf_propagates_and_frees_the_recursion
    fake = RecursionEventFake.new
    fake.recursion_leaf_codes = [Hegel::LibHegel::HEGEL_E_STOP_TEST]
    generator = recursive(integers) { |subtrees| arrays(subtrees) }

    assert_raises(Hegel::StopTest) { generator.do_draw(fake_test_case(fake)) }
    assert_equal [[:start, generator.label], :new_recursion, [:branch, 0], :leaf, :free, [:stop, false]], fake.calls
    assert_equal 1, fake.freed_recursions.size
  end

  def test_an_abandoned_attempt_inside_a_filter_closes_no_span_as_rejected
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true]
    fake.recursion_leaf_codes = [RETRY]
    branches = []
    generator = recursive(integers) { |subtrees| subtrees.filter { true }.tap { |b| branches << b } }

    generator.do_draw(fake_test_case(fake))
    assert_equal [
      [:start, generator.label], :new_recursion, [:branch, 0],
      [:start, branches.first.label], [:start, generator.label], [:branch, 1], :leaf, :retry,
      [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false]
    ], fake.calls
  end

  # The four ways a branch's own code can meet the abandoned attempt all end
  # in the same retry, with nothing they did after it reaching the engine.
  def test_a_branch_cannot_keep_an_abandoned_attempt
    bodies = {
      rescue_standard_error: lambda do |dtc, subtrees|
        dtc.draw(subtrees)
      rescue
        :rescued
      end,
      rescue_exception_and_return: lambda do |dtc, subtrees|
        dtc.draw(subtrees)
      rescue Exception # standard:disable Lint/RescueException
        :swallowed
      end,
      rescue_exception_and_draw: lambda do |dtc, subtrees|
        begin
          dtc.draw(subtrees)
        rescue Exception # standard:disable Lint/RescueException
          nil
        end
        dtc.draw(integers)
      end
    }

    bodies.each do |name, body|
      fake = RecursionEventFake.new
      fake.recursion_branch_values = [true]
      fake.recursion_leaf_codes = [RETRY]
      composites = []
      generator = recursive(integers) do |subtrees|
        composite { |dtc| body.call(dtc, subtrees) }.tap { |c| composites << c }
      end

      assert_equal 0, generator.do_draw(fake_test_case(fake)), name
      assert_equal [
        [:start, generator.label], :new_recursion, [:branch, 0],
        [:start, composites.first.label], [:start, generator.label], [:branch, 1], :leaf, :retry,
        [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false]
      ], fake.calls, name
    end
  end

  def test_an_ensure_that_raises_while_an_attempt_unwinds_propagates_its_own_error
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true]
    fake.recursion_leaf_codes = [RETRY]
    composites = []
    generator = recursive(integers) do |subtrees|
      composite do |dtc|
        dtc.draw(subtrees)
      ensure
        raise "cleanup failed"
      end.tap { |c| composites << c }
    end

    error = assert_raises(RuntimeError) { generator.do_draw(fake_test_case(fake)) }
    assert_equal "cleanup failed", error.message
    assert_equal [[:start, generator.label], :new_recursion, [:branch, 0], [:start, composites.first.label],
      [:start, generator.label], [:branch, 1], :leaf, :free], fake.calls
  end

  # The body that rescues that error and draws again gets the abandoned
  # attempt back, and the run discards the case.
  def test_an_attempt_left_abandoned_by_a_raising_ensure_discards_the_case
    fake = Hegel::LibHegel::Fake.new
    fake.test_case_count = 1
    fake.recursion_branch_values = [true]
    fake.recursion_leaf_codes = [RETRY]
    generator = recursive(integers) do |subtrees|
      composite do |dtc|
        dtc.draw(subtrees)
      ensure
        raise "cleanup failed"
      end
    end

    Hegel.test(impl: fake, output: StringIO.new) do |tc|
      begin
        tc.draw(generator)
      rescue RuntimeError
        nil
      end
      tc.draw(integers)
    end

    assert_equal [Hegel::LibHegel::HEGEL_STATUS_INVALID], fake.marked_statuses
  end

  def test_a_retry_in_a_nested_recursive_draw_leaves_the_outer_one_alone
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [false, true, false]
    fake.recursion_leaf_codes = [Hegel::LibHegel::HEGEL_OK, RETRY]
    fake.collection_more_count = 1
    inner = recursive(integers) { |subtrees| arrays(subtrees) }
    outer = recursive(inner) { |subtrees| arrays(subtrees) }

    assert_equal 0, outer.do_draw(fake_test_case(fake))
    assert_equal [
      [:start, outer.label], :new_recursion, [:branch, 0], :leaf,
      [:start, inner.label], :new_recursion, [:branch, 0],
      [:start, arrays(inner).label], :new_collection, :more, [:start, inner.label], [:start, inner.label],
      [:branch, 1], :leaf, :collection_free, :retry,
      [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false],
      :finish, :free, [:stop, false]
    ], fake.calls
  end

  # The inner draw's leaves are subtrees of the outer one, so an outer leaf
  # over budget unwinds through the inner draw, which frees its own
  # recursion and leaves the retry to the outer.
  def test_a_retry_of_the_outer_recursive_draw_passes_through_an_inner_one
    fake = RecursionEventFake.new
    fake.recursion_branch_values = [true, false, false]
    fake.recursion_leaf_codes = [Hegel::LibHegel::HEGEL_OK, RETRY]
    inners = []
    outer = recursive(integers) do |subtrees|
      recursive(subtrees) { |inner_subtrees| arrays(inner_subtrees) }.tap { |inner| inners << inner }
    end

    assert_equal 0, outer.do_draw(fake_test_case(fake))
    assert_equal [
      [:start, outer.label], :new_recursion, [:branch, 0],
      [:start, inners.first.label], :new_recursion, [:branch, 0], :leaf,
      [:start, outer.label], [:branch, 1], :leaf, :free, :retry,
      [:branch, 0], :leaf, :integer, :finish, :free, [:stop, false]
    ], fake.calls
  end

  def test_a_subtree_drawn_after_its_recursive_draw_raises
    fake = Hegel::LibHegel::Fake.new
    fake.recursion_branch_values = [true]
    kept = nil
    generator = recursive(integers) do |subtrees|
      kept = subtrees
      arrays(subtrees)
    end
    tc = fake_test_case(fake)
    generator.do_draw(tc)

    error = assert_raises(Hegel::Error) { kept.do_draw(tc) }
    assert_equal "recursive: a subtree generator was drawn outside the draw that made it", error.message
  end

  def test_the_default_budgets_reach_the_engine
    fake = Hegel::LibHegel::Fake.new
    recursive(integers) { |subtrees| arrays(subtrees) }.do_draw(fake_test_case(fake))
    recursive(integers, max_depth: 0, max_leaves: 2**64 - 1) { |subtrees| arrays(subtrees) }
      .do_draw(fake_test_case(fake))

    assert_equal [[32, 100], [0, 2**64 - 1]], fake.new_recursion_calls
  end

  def test_each_invalid_argument_raises_at_draw_time_with_its_own_message
    branch = ->(subtrees) { arrays(subtrees) }
    cases = {
      recursive(integers) => "recursive: block is required",
      recursive(5, &branch) => "recursive: leaf must be a generator, got 5",
      recursive(integers, max_depth: -1, &branch) =>
        "recursive: max_depth must be an Integer between 0 and 2**64 - 1, got -1",
      recursive(integers, max_depth: 2**64, &branch) =>
        "recursive: max_depth must be an Integer between 0 and 2**64 - 1, got 18446744073709551616",
      recursive(integers, max_depth: 1.0, &branch) =>
        "recursive: max_depth must be an Integer between 0 and 2**64 - 1, got 1.0",
      recursive(integers, max_leaves: -1, &branch) =>
        "recursive: max_leaves must be an Integer between 0 and 2**64 - 1, got -1",
      recursive(integers, max_leaves: 2**64, &branch) =>
        "recursive: max_leaves must be an Integer between 0 and 2**64 - 1, got 18446744073709551616",
      recursive(integers, max_leaves: nil, &branch) =>
        "recursive: max_leaves must be an Integer between 0 and 2**64 - 1, got nil"
    }

    cases.each do |generator, message|
      fake = RecursionEventFake.new
      error = assert_raises(Hegel::Error) { generator.do_draw(fake_test_case(fake)) }
      assert_equal message, error.message
      assert_empty fake.calls, message
    end
  end

  def test_a_block_that_returns_something_other_than_a_generator_raises_at_draw_time
    fake = Hegel::LibHegel::Fake.new
    fake.recursion_branch_values = [true]
    generator = recursive(integers) { |_subtrees| 5 }

    error = assert_raises(Hegel::Error) { generator.do_draw(fake_test_case(fake)) }
    assert_equal "recursive: the block must return a generator, got 5", error.message
    assert_equal 1, fake.freed_recursions.size
  end

  def test_the_label_names_the_leaf_generator
    assert_equal Hegel::LibHegel.label_combine([Hegel::Generators::RecursiveGenerator.label, integers.label]),
      recursive(integers) { |s| arrays(s) }.label
    assert_equal recursive(integers) { |s| arrays(s) }.label, recursive(integers, max_depth: 1) { |s| tuples(s) }.label
    refute_equal recursive(integers) { |s| arrays(s) }.label, recursive(text) { |s| arrays(s) }.label
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
