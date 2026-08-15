# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestStateful < Minitest::Test
  # A run that leaves ./.hegel behind means the mandatory database-disable
  # step regressed, the same check test/hegel/test_generators.rb's own
  # #teardown makes for every real-engine test in that file.
  def teardown
    refute Dir.exist?(File.join(Dir.pwd, ".hegel")),
      "a run must not leave a .hegel directory behind"
  end

  # ---- declaration (no real engine: these only read StateMachine's own
  # class-level bookkeeping, never call Hegel::Stateful.run against libhegel) ----

  class DeclarationOrderMachine < Hegel::StateMachine
    rule(:push) {}
    rule(:pop) {}
    invariant(:size_agrees) {}
    invariant(:never_negative) {}
  end

  def test_rules_and_invariants_register_in_declaration_order
    assert_equal %w[push pop], DeclarationOrderMachine.rule_definitions.keys
    assert_equal %w[size_agrees never_negative], DeclarationOrderMachine.invariant_definitions.keys
  end

  def test_declaring_the_same_rule_name_twice_on_one_class_raises
    error = assert_raises(Hegel::Error) do
      Class.new(Hegel::StateMachine) do
        rule(:push) {}
        rule(:push) {}
      end
    end

    assert_includes error.message, "hegel: "
    assert_includes error.message, "push"
  end

  class RedeclareBaseMachine < Hegel::StateMachine
    rule(:push) { :base_push }
    rule(:pop) { :base_pop }
  end

  class RedeclareChildMachine < RedeclareBaseMachine
    rule(:push) { :child_push }
  end

  # docs/adr/0010: "A subclass declaring an inherited name replaces it, the
  # way a redefined method does." #call below runs each block directly (no
  # #instance_exec target needed -- neither block reads self) to read back
  # which definition #rule_definitions kept, and the assertion on .keys
  # pins that the replaced name keeps its original, inherited position
  # rather than moving to the end.
  def test_subclass_redeclaring_an_inherited_rule_replaces_it_and_keeps_the_rest
    definitions = RedeclareChildMachine.rule_definitions

    assert_equal %w[push pop], definitions.keys
    assert_equal :child_push, definitions.fetch("push").call
    assert_equal :base_pop, definitions.fetch("pop").call
  end

  class NoRulesMachine < Hegel::StateMachine
    invariant(:always) {}
  end

  # The zero-rules guard raises before Hegel::Stateful.run makes any
  # libhegel call, so this needs neither a running Hegel.test block nor a
  # real +tc+ -- +tc+ is nil here to prove exactly that.
  def test_running_a_machine_with_no_rules_raises_before_touching_the_engine
    error = assert_raises(Hegel::Error) { Hegel::Stateful.run(NoRulesMachine.new, nil) }

    assert_includes error.message, "hegel: "
    assert_includes error.message, "no rules"
  end

  class GeneratorMachine < Hegel::StateMachine
    attr_reader :built

    rule(:build) { |_tc| @built = integers(min_value: 0, max_value: 9) }
  end

  # Hegel::StateMachine includes Hegel::Syntax::Methods (docs/adr/0010), so
  # a rule block reaches a generator method bare. Constructing the
  # generator does not need a real Hegel::TestCase -- only #do_draw does --
  # so this runs the rule block directly via #instance_exec, the same way
  # Hegel::Stateful.run itself invokes one, without opening the engine.
  def test_generator_methods_are_callable_bare_inside_a_rule_block
    machine = GeneratorMachine.new
    machine.instance_exec(nil, &GeneratorMachine.rule_definitions.fetch("build"))

    assert_kind_of Hegel::Generators::IntegerGenerator, machine.built
  end

  # ---- running (real engine: these all exercise Hegel::Stateful.run's
  # loop, so they need libhegel actually driving Hegel::TestCase) ----

  # A stack whose #push does not enforce its own capacity -- the bug this
  # machine's invariant is built to catch. A correct model caps at 2, so
  # divergence appears exactly on the 3rd push.
  class UncappedStack
    def initialize
      @items = []
    end

    def push(x)
      @items << x
    end

    def size
      @items.size
    end
  end

  # Only one rule and one invariant: with a single rule the engine always
  # picks it, so what shrinking has to find is purely the minimal *count*
  # of pushes, one clean test of the HEGEL_LABEL_STATEFUL_RULE span's
  # placement (the shrink-quality role test/hegel/test_generators.rb's own
  # composed-with-arrays tests play for HEGEL_LABEL_LIST/LIST_ELEMENT; see
  # the class comment there and the real-engine-tests skill's "Shrinking is
  # what makes a span test bite").
  class OverflowStackMachine < Hegel::StateMachine
    CAPACITY = 2

    def initialize
      @stack = UncappedStack.new
      @model_size = 0
    end

    rule(:push) do |tc|
      tc.draw(integers(min_value: 0, max_value: 9))
      @stack.push(0)
      @model_size += 1 if @model_size < CAPACITY
    end

    invariant(:size_agrees) do
      unless @stack.size == @model_size
        raise "size disagreed: stack has #{@stack.size}, model expects #{@model_size}"
      end
    end
  end

  # The central test of this batch: the shrunk counterexample is exactly 3
  # pushes, no more. A span placed on the wrong draw still passes this test
  # eventually but shrinks to something larger than 3 -- the same failure
  # mode the skill's "Shrinking is what makes a span test bite" describes.
  def test_stateful_run_shrinks_to_the_minimal_step_count_that_breaks_the_invariant
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) { |tc| Hegel::Stateful.run(OverflowStackMachine.new, tc) }
    end

    assert_includes error.message, "size disagreed"
    assert_includes output.string, "Step 1: push"
    assert_includes output.string, "Step 2: push"
    assert_includes output.string, "Step 3: push"
    refute_includes output.string, "Step 4:"
  end

  # One rule, two branches: the first application within a test case always
  # calls tc.assume(false) (forced, not drawn -- see #initialize), and every
  # application after that fails or rejects on a coin flip. Forcing the
  # first application deterministically, rather than leaving it to the
  # draw, is what keeps +reject_counter+'s assertion below from racing
  # against the draw that decides when #step first raises: a single rule
  # also sidesteps hegel.h's own "each test case enables a random subset of
  # rules" (a second, always-failing rule could be excluded from a case's
  # subset entirely, leaving nothing here to prove).
  #
  # +reject_counter+ is shared across every body invocation this run makes
  # (generation and shrink alike), so it observes whether tc.assume(false)
  # ever actually ran, distinct from the shrunk report (which, once
  # minimal, may show no rejected step at all).
  #
  # "(0 discarded)" is the load-bearing assertion, and it is not a
  # probabilistic one: Hegel::Runner::GenerationStats only counts a case as
  # discarded when Hegel::AssumeFailed reaches Hegel::Runner.classify, and
  # this test body's only assume/reject calls are the ones inside #step. If
  # Hegel::Stateful.run correctly catches every one of those inside the
  # rule loop (never letting one escape as the whole case's own rejection),
  # no case is ever discarded -- see Hegel::Stateful.apply_rule's own
  # comment for the AssumeFailed/StopTest distinction this pins.
  class RejectingMachine < Hegel::StateMachine
    def initialize(reject_counter)
      @reject_counter = reject_counter
      @attempts = 0
    end

    rule(:step) do |tc|
      should_fail = @attempts.positive? && tc.draw_boolean
      @attempts += 1
      if should_fail
        raise "always fails"
      else
        @reject_counter[0] += 1
        tc.assume(false)
      end
    end
  end

  def test_assume_false_inside_a_rule_rejects_only_that_rule_not_the_whole_test_case
    output = StringIO.new
    reject_counter = [0]

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) { |tc| Hegel::Stateful.run(RejectingMachine.new(reject_counter), tc) }
    end

    assert_includes error.message, "always fails"
    assert_operator reject_counter[0], :>, 0, "tc.assume(false) never ran, so this run does not test what it claims"
    assert_includes output.string, "(0 discarded)"
  end

  # #invariant_checks counts every invariant call this machine sees
  # (initial plus one per successful rule); #successful_rules counts only
  # completed rule applications. The property under test --
  # invariant_checks == 1 + successful_rules -- is checked inside the
  # Hegel.test body itself, per test case, so a violation surfaces as this
  # run's own failure rather than needing a separate counter comparison
  # after the fact.
  class CountingMachine < Hegel::StateMachine
    attr_reader :invariant_checks, :successful_rules

    def initialize
      @invariant_checks = 0
      @successful_rules = 0
    end

    rule(:step) { |_tc| @successful_rules += 1 }

    invariant(:count) { @invariant_checks += 1 }
  end

  def test_invariant_runs_once_initially_and_once_per_successful_rule
    Hegel.test(test_cases: 3, verbosity: :quiet) do |tc|
      machine = CountingMachine.new
      Hegel::Stateful.run(machine, tc)
      unless machine.invariant_checks == 1 + machine.successful_rules
        raise "invariant_checks (#{machine.invariant_checks}) != 1 + successful_rules (#{machine.successful_rules})"
      end
    end
  end

  class AlwaysFailingInvariantMachine < Hegel::StateMachine
    rule(:noop) {}

    invariant(:always_false) { raise "invariant broken" }
  end

  # The initial invariant check (before any rule runs) already fails here,
  # so this pins that a failing invariant becomes the running test case's
  # own failure -- Hegel::Stateful.run raises straight out of Hegel.test,
  # the same as any other body exception.
  def test_a_failing_invariant_becomes_the_test_cases_failure
    error = assert_raises(RuntimeError) do
      Hegel.test(verbosity: :quiet) { |tc| Hegel::Stateful.run(AlwaysFailingInvariantMachine.new, tc) }
    end

    assert_includes error.message, "invariant broken"
  end

  class StepCountMachine < Hegel::StateMachine
    attr_reader :steps

    def initialize
      @steps = 0
    end

    rule(:step) { |_tc| @steps += 1 }
  end

  # hegel.h documents hegel_settings_set_stateful_step_count's n as both the
  # minimum and the maximum: "each test case runs at least one step and at
  # most n". With n = 1 and a rule that never rejects, #steps is exactly 1
  # on every case, not just bounded by 1 -- the strongest claim this
  # setting supports without also asserting against an unseeded run (the
  # real-engine-tests skill's "Do not assert that a search got luckier").
  def test_stateful_step_count_bounds_the_number_of_steps_per_case
    Hegel.test(stateful_step_count: 1, test_cases: 5, verbosity: :quiet) do |tc|
      machine = StepCountMachine.new
      Hegel::Stateful.run(machine, tc)
      raise "expected exactly 1 step, got #{machine.steps}" unless machine.steps == 1
    end
  end

  class ImmediateFailureMachine < Hegel::StateMachine
    rule(:go) { |_tc| raise "boom" }
  end

  # ImmediateFailureMachine declares no invariants, so #new_state_machine's
  # own invariant_names is empty -- exercising the header's other documented
  # case (test/hegel/test_lib_hegel.rb's own
  # test_real_new_state_machine_accepts_an_empty_invariant_names_array pins
  # it at the binding layer; this is the same case one level up). The one
  # rule fails on its very first application, so the report needs no
  # shrinking to reach its minimal form, and "Step 1: go" is the whole
  # step list.
  def test_report_shows_the_initial_invariant_check_and_the_first_step_by_name
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) { |tc| Hegel::Stateful.run(ImmediateFailureMachine.new, tc) }
    end

    assert_includes output.string, "Initial invariant check."
    assert_includes output.string, "Step 1: go"
  end

  # Hegel::Stateful.apply_rule rescues Exception, so a rule is a second
  # place (after Hegel::Runner.classify, which test_runner.rb covers) where
  # Ctrl-C could be swallowed and turned into a step that merely passed.
  # Interrupt stands in for all of Hegel::FATAL_EXCEPTIONS here.
  #
  # What this pins is that the exception leaves #apply_rule unchanged, not
  # which rescue branch let it out: the branch above the fatal one re-raises
  # too, so both orderings pass this. The ordering earns its place by not
  # answering a NoMemoryError with another native call, which is a claim
  # about a path no test can drive.
  class InterruptingMachine < Hegel::StateMachine
    rule :go do
      raise Interrupt
    end
  end

  def test_a_fatal_exception_raised_inside_a_rule_propagates
    assert_raises(Interrupt) do
      Hegel.test(verbosity: :quiet, output: StringIO.new) do |tc|
        Hegel::Stateful.run(InterruptingMachine.new, tc)
      end
    end
  end

  # ---- Hegel::Stateful::Pool (real engine: docs/adr/0011 has the ownership
  # decision behind this class's shape) ----

  def test_pool_add_then_values_reusable_returns_the_added_value
    Hegel.test(test_cases: 5, verbosity: :quiet) do |tc|
      pool = Hegel::Stateful::Pool.new(tc)
      raise "a fresh pool must be empty" unless pool.empty?

      pool.add(42)
      raise "a pool holding a value must not be empty" if pool.empty?

      value = tc.draw(pool.values_reusable)
      raise "expected 42, got #{value}" unless value == 42
    end
  end

  # #values_reusable must leave its chosen value in the pool: two draws in a
  # row against a pool holding one value both have to succeed, and #size
  # must still read 1 afterward.
  def test_values_reusable_does_not_remove_the_value_from_the_pool
    Hegel.test(test_cases: 5, verbosity: :quiet) do |tc|
      pool = Hegel::Stateful::Pool.new(tc)
      pool.add(1)
      tc.draw(pool.values_reusable)
      tc.draw(pool.values_reusable)
      raise "pool size changed: #{pool.size}" unless pool.size == 1
    end
  end

  def test_values_consumed_removes_the_drawn_value_from_the_pool
    Hegel.test(test_cases: 5, verbosity: :quiet) do |tc|
      pool = Hegel::Stateful::Pool.new(tc)
      pool.add(1)
      pool.add(2)
      tc.draw(pool.values_consumed)
      raise "expected size 1, got #{pool.size}" unless pool.size == 1
    end
  end

  # A pool draw outside a rule behaves like any other assume/reject call:
  # HEGEL_E_ASSUME from an empty pool translates to Hegel::AssumeFailed,
  # which Hegel::Runner.classify discards the whole case for. A call
  # counter, not the drawn value, decides which cases add to the pool
  # first (the same shape test_runner.rb's own
  # test_assume_false_discards_the_case_and_counts_toward_discarded uses),
  # so this cannot flake on libhegel's own randomness. The draw_integer
  # call is required, not decoration: the real-engine-tests skill's own
  # "The run stops early if a case has nothing to vary" notes that a case
  # discarding having drawn nothing ends the run after one trial.
  def test_drawing_from_an_empty_pool_outside_a_rule_raises_assume_failed_and_discards_the_case
    output = StringIO.new
    calls = 0

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        calls += 1
        tc.draw_integer(0, 10)
        pool = Hegel::Stateful::Pool.new(tc)
        pool.add(1) if calls > 2
        tc.draw(pool.values_consumed)
        raise "boom"
      end
    end

    assert_includes error.message, "boom"
    assert_includes output.string, "(2 discarded)"
  end

  # Same machine shape as RejectingMachine above, with an empty pool draw in
  # place of tc.assume(false) as the source of Hegel::AssumeFailed: proves
  # Hegel::Stateful.apply_rule's rescue catches this one the same way,
  # rejecting only the rule that drew it rather than the whole test case.
  # "(0 discarded)" is the load-bearing assertion for the same reason it is
  # there -- see that test's own comment.
  class PoolRejectingMachine < Hegel::StateMachine
    def initialize(tc, reject_counter)
      @pool = Hegel::Stateful::Pool.new(tc)
      @reject_counter = reject_counter
      @attempts = 0
    end

    rule(:step) do |tc|
      should_fail = @attempts.positive? && tc.draw_boolean
      @attempts += 1
      if should_fail
        raise "always fails"
      else
        @reject_counter[0] += 1
        tc.draw(@pool.values_consumed)
      end
    end
  end

  def test_drawing_from_an_empty_pool_inside_a_rule_rejects_only_that_rule_not_the_whole_test_case
    output = StringIO.new
    reject_counter = [0]

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) { |tc| Hegel::Stateful.run(PoolRejectingMachine.new(tc, reject_counter), tc) }
    end

    assert_includes error.message, "always fails"
    assert_operator reject_counter[0], :>, 0,
      "the empty-pool draw never ran, so this run does not test what it claims"
    assert_includes output.string, "(0 discarded)"
  end

  # One pool, two rules: alloc adds a fresh handle, free draws one back out.
  # #free below draws #values_reusable rather than #values_consumed, an
  # injected bug that lets the same handle be freed twice -- the divergence
  # from the model (@live) this shrink test targets.
  class DoubleFreeMachine < Hegel::StateMachine
    def initialize(tc)
      @pool = Hegel::Stateful::Pool.new(tc)
      @live = []
    end

    rule(:alloc) do |tc|
      handle = tc.draw(integers(min_value: 0, max_value: 9))
      @pool.add(handle)
      @live << handle
    end

    rule(:free) do |tc|
      handle = tc.draw(@pool.values_reusable)
      raise "double free: #{handle}" unless @live.delete(handle)
    end
  end

  # The minimal counterexample is exactly 3 steps: one alloc (so a handle
  # exists), then two frees of it. #values_reusable's own not-removing
  # behaviour is what lets the second free see the same handle again --
  # if a value drawn from the pool were removed the way #values_consumed
  # removes it, the second free would draw from an empty pool and reject
  # that rule instead of reaching the bug, and this machine would never
  # fail at all. A shrink that lands anywhere but 3 steps means that
  # behaviour regressed, the same span-quality role
  # test_stateful_run_shrinks_to_the_minimal_step_count_that_breaks_the_invariant
  # plays above.
  def test_stateful_pool_run_shrinks_to_the_minimal_alloc_then_double_free_sequence
    output = StringIO.new

    error = assert_raises(RuntimeError) do
      Hegel.test(output: output) { |tc| Hegel::Stateful.run(DoubleFreeMachine.new(tc), tc) }
    end

    assert_includes error.message, "double free"
    assert_includes output.string, "Step 1: alloc"
    assert_includes output.string, "Step 2: free"
    assert_includes output.string, "Step 3: free"
    refute_includes output.string, "Step 4:"
  end

  # Pinned because Hegel::TestCase#draw is what pool_generate goes through
  # (docs/adr/0011): the chosen value is recorded and named for the report
  # the same way any other draw is.
  def test_pool_draw_appears_in_the_failure_report
    output = StringIO.new

    assert_raises(RuntimeError) do
      Hegel.test(output: output) do |tc|
        pool = Hegel::Stateful::Pool.new(tc)
        pool.add(42)
        value = tc.draw(pool.values_reusable, label: "handle")
        raise "boom: #{value}"
      end
    end

    assert_includes output.string, "handle = 42"
  end
end
