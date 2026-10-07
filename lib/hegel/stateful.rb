# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"
require_relative "stateful/pool"

module Hegel
  # Runs one stateful (model-based) test: drives libhegel's own state-machine
  # loop (hegel_new_state_machine and the three calls that go with it) against
  # a Hegel::StateMachine instance's declared rules and invariants. Call it
  # from inside an ordinary Hegel.test block, the same way any other draw
  # happens:
  #
  #   Hegel.test { |tc| Hegel::Stateful.run(StackMachine.new, tc) }
  #
  # A module function, not a Hegel::StateMachine instance method, so that
  # class stays limited to declaration -- the same split hegel-rust's own
  # src/stateful.rs draws between the StateMachine trait and its free
  # function `run`, which this module's own #run is ported from; see that
  # file's comments for the reasoning behind the ordering below.
  module Stateful
    module_function

    # The span label of one round, which at concurrency 1 runs one rule.
    ROUND_LABEL = LibHegel.label_from_name("hegel-ruby.Hegel::Stateful.round")

    # hegel-rust, hegel-go, and hegel-java all default a machine's step count
    # to 50. The engine has no default of its own.
    DEFAULT_STEP_COUNT = 50

    # +machine+ is a Hegel::StateMachine instance; +tc+ the running
    # Hegel::TestCase. +step_count+ is the most rounds, and so the most
    # rules, one test case runs. It must be at least 1, or the engine
    # rejects it.
    #
    # Raises Hegel::Error before making any libhegel call when +machine+
    # declares no rules: hegel.h documents hegel_new_state_machine's
    # rule_names as required to be non-empty, and there is nothing useful to
    # run without one.
    def run(machine, tc, step_count: DEFAULT_STEP_COUNT)
      rules = machine.class.rule_definitions
      raise Hegel::Error, "hegel: #{machine.class} has no rules; declare at least one with `rule`" if rules.empty?

      invariants = machine.class.invariant_definitions
      state_machine = tc.new_state_machine(
        rules.keys, invariants.keys, invariants.values.map(&:always_run), step_count
      )
      begin
        tc.note { "Initial invariant check." }
        run_invariants(machine, invariants.values, tc)
        drive(machine, rules, invariants.values, state_machine, tc)
        tc.note { "Final invariant check." }
        run_invariants(machine, invariants.values, tc)
      ensure
        tc.state_machine_free(state_machine)
      end
    end

    # Runs rounds until libhegel ends the machine. Each round asks for a
    # group first, which the header requires before the first rule too, then
    # pulls rules until the round ends. Between rounds, each invariant runs
    # only when the engine samples it (see
    # Hegel::TestCase#state_machine_should_check_invariant), as hegel-rust,
    # hegel-go, and hegel-java do. The initial and final checks in #run are
    # the ones that always happen.
    def drive(machine, rules, invariants, state_machine, tc)
      rule_names = rules.keys
      steps_attempted = 0
      loop do
        tc.start_span(ROUND_LABEL)
        if tc.state_machine_next_group(state_machine) == LibHegel::HEGEL_STATE_MACHINE_DONE
          tc.stop_span(discard: false)
          break
        end

        rejected = false
        loop do
          rule_index = tc.state_machine_next_rule(state_machine)
          break if rule_index == LibHegel::HEGEL_STATE_MACHINE_DONE

          name = rule_names[rule_index]
          steps_attempted += 1
          tc.note { "Step #{steps_attempted}: #{name}" }
          rejected = true unless apply_rule(machine, rules.fetch(name), state_machine, tc)
        end
        tc.stop_span(discard: rejected)
        run_sampled_invariants(machine, invariants, state_machine, tc)
      end
    end

    # Returns false when the rule stopped on a failed assumption, and true
    # when it completed.
    #
    # standard:disable Lint/RescueException -- deliberate, the same reason
    # Hegel::Runner.classify's own `rescue Exception` is: Hegel::AssumeFailed
    # and Hegel::StopTest both descend from Exception, not StandardError, so
    # only `rescue Exception` sees every path a rule can take. Every branch
    # other than AssumeFailed re-raises what it caught unchanged -- this
    # never reclassifies an exception or swallows one, it only guarantees
    # the round's span closes first, so a half-applied rule is never left
    # mid-span when the exception unwinds past this method.
    #
    # Hegel::FATAL_EXCEPTIONS goes first and closes no span. They say the
    # process is ending, so the span has no reader left to matter to, and
    # answering a NoMemoryError with another native call is the wrong move.
    # A rule is the one place in this library where a fatal exception is
    # raised inside an open span, so this is where that ordering has to be
    # written.
    #
    # tc.assume(false) inside a rule is not the same event as one raised
    # directly inside a Hegel.test block: it rejects only this rule (told to
    # libhegel via #state_machine_rule_rejected, so the rejected round
    # does not count toward the step budget) and the loop keeps going, where
    # Hegel::Runner.classify's own AssumeFailed handling discards the whole
    # test case. Hegel::Runner.classify never sees this one: it is caught
    # and handled right here.
    def apply_rule(machine, block, state_machine, tc)
      machine.instance_exec(tc, &block)
      true
    rescue *Hegel::FATAL_EXCEPTIONS
      raise
    rescue Hegel::AssumeFailed
      tc.state_machine_rule_rejected(state_machine)
      tc.note { "Rule stopped early due to violated assumption." }
      false
    rescue Exception
      tc.stop_span(discard: false)
      raise
    end
    # standard:enable Lint/RescueException

    # Runs every invariant, in declaration order, via #instance_exec -- same
    # argument contract as a rule block (Hegel::StateMachine.invariant).
    def run_invariants(machine, invariants, tc)
      invariants.each { |invariant| machine.instance_exec(tc, &invariant.block) }
    end

    # Runs each invariant the engine samples at this join point, in
    # declaration order.
    def run_sampled_invariants(machine, invariants, state_machine, tc)
      invariants.each_with_index do |invariant, index|
        next unless tc.state_machine_should_check_invariant(state_machine, index)

        machine.instance_exec(tc, &invariant.block)
      end
    end
  end
end
