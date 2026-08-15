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

    # +machine+ is a Hegel::StateMachine instance; +tc+ the running
    # Hegel::TestCase.
    #
    # Raises Hegel::Error before making any libhegel call when +machine+
    # declares no rules: hegel.h documents hegel_new_state_machine's
    # rule_names as required to be non-empty, and there is nothing useful to
    # run without one.
    def run(machine, tc)
      rules = machine.class.rule_definitions
      raise Hegel::Error, "hegel: #{machine.class} has no rules; declare at least one with `rule`" if rules.empty?

      invariants = machine.class.invariant_definitions
      rule_names = rules.keys
      state_machine = tc.new_state_machine(rule_names, invariants.keys)
      begin
        tc.note { "Initial invariant check." }
        run_invariants(machine, invariants, tc)
        drive(machine, rules, rule_names, invariants, state_machine, tc)
      ensure
        tc.state_machine_free(state_machine)
      end
    end

    # Repeatedly asks +state_machine+ for the next rule to run and applies
    # it, until libhegel reports the step budget for this test case spent.
    #
    # Measured against libhegel 0.32.5, unseeded, on the capacity-2 stack
    # shrink-quality test below (test/hegel/test_stateful.rb,
    # test_stateful_run_shrinks_to_the_minimal_step_count_that_breaks_the_
    # invariant): closing the HEGEL_LABEL_STATEFUL_RULE span with
    # stop_span(discard: false) on the DONE branch, right before breaking
    # out of this loop, and leaving it open instead (matching hegel-rust's
    # own `run`, which never closes that last span) both shrink the same
    # failure to the same 3-step counterexample every time, 20 runs each.
    # This keeps hegel-rust's own choice -- an unclosed span at DONE --
    # since nothing measured favours the extra stop_span call.
    def drive(machine, rules, rule_names, invariants, state_machine, tc)
      steps_attempted = 0
      loop do
        tc.start_span(LibHegel::HEGEL_LABEL_STATEFUL_RULE)
        rule_index = tc.state_machine_next_rule(state_machine)
        break if rule_index == LibHegel::HEGEL_STATE_MACHINE_DONE

        name = rule_names[rule_index]
        steps_attempted += 1
        tc.note { "Step #{steps_attempted}: #{name}" }
        apply_rule(machine, rules.fetch(name), invariants, state_machine, tc)
      end
    end

    # standard:disable Lint/RescueException -- deliberate, the same reason
    # Hegel::Runner.classify's own `rescue Exception` is: Hegel::AssumeFailed
    # and Hegel::StopTest both descend from Exception, not StandardError, so
    # only `rescue Exception` sees every path a rule can take. Every branch
    # other than AssumeFailed re-raises what it caught unchanged -- this
    # never reclassifies an exception or swallows one, it only guarantees
    # the span closes first, so a half-applied rule is never left mid-span
    # when the exception unwinds past this method.
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
    # libhegel via #state_machine_rule_rejected, so the rejected attempt
    # does not count toward the step budget) and the loop keeps going, where
    # Hegel::Runner.classify's own AssumeFailed handling discards the whole
    # test case. Hegel::Runner.classify never sees this one: it is caught
    # and handled right here.
    def apply_rule(machine, block, invariants, state_machine, tc)
      machine.instance_exec(tc, &block)
    rescue *Hegel::FATAL_EXCEPTIONS
      raise
    rescue Hegel::AssumeFailed
      tc.state_machine_rule_rejected(state_machine)
      tc.stop_span(discard: true)
      tc.note { "Rule stopped early due to violated assumption." }
    rescue Exception
      tc.stop_span(discard: false)
      raise
    else
      tc.stop_span(discard: false)
      run_invariants(machine, invariants, tc)
    end
    # standard:enable Lint/RescueException

    # Runs every invariant, in declaration order, via #instance_exec -- same
    # argument contract as a rule block (Hegel::StateMachine.invariant).
    def run_invariants(machine, invariants, tc)
      invariants.each_value { |block| machine.instance_exec(tc, &block) }
    end
  end
end
