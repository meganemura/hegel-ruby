# frozen_string_literal: true

require "hegel"

module Hegel
  # Hegel-testing-Hegel helpers for the generator conformance suite (see
  # test/hegel/test_generators.rb and the per-generator test files built on
  # top of it): a Ruby port of hegel-java's own test/.../Utils.java, so a
  # generator's test can assert a property against the real engine, or ask
  # it to shrink a counterexample to a minimal one, in a single line
  # instead of a hand-rolled Hegel.test block.
  #
  # This lives under test/support/, not lib/: it is infrastructure for this
  # gem's own test suite, not part of what a caller who installs hegeltest
  # gets (hegeltest.gemspec's file list drops all of test/). A test class
  # includes this module the same way it includes Hegel::Syntax::Methods
  # for booleans/integers/etc; #assert and #refute below come from that
  # class's own Minitest::Test, not from this module.
  module Conformance
    # Raised from inside a Hegel.test block by #minimal once #condition
    # holds, so Hegel::Runner treats the case as a counterexample and
    # shrinks it -- the same trick hegel-java's own minimal plays with
    # AssertionError. A dedicated class, not RuntimeError: a bug in the
    # generator under test that happens to raise RuntimeError must still
    # read as "the generator failed", not get relabeled "condition
    # satisfied" because the exception class happened to match this one
    # too.
    class ConditionSatisfied < StandardError; end

    # A puts-only stand-in for output:, given to every Hegel.test call
    # below alongside verbosity: :quiet. verbosity: :quiet alone already
    # stops Hegel::Runner#replay from writing a failure report at all (see
    # lib/hegel/runner.rb), but these four helpers back roughly 20
    # generators' worth of tests and run hundreds of times per suite; this
    # is a second, independent seal on that output, not a substitute for
    # the first one.
    class Discard
      def puts(*)
      end
    end

    DISCARD = Discard.new

    # The two keywords every Hegel.test call below shares: quiet
    # libhegel-side verbosity, and a discarded output: (see DISCARD
    # above). Hegel::Runner already disables the example database on every
    # run, unconditionally (lib/hegel/runner.rb's settings_set_database
    # call) -- unlike hegel-java's Utils, which passes Database.disabled()
    # itself, there is nothing left here to disable a second time.
    QUIET_SETTINGS = {verbosity: :quiet, output: DISCARD}.freeze

    # Asserts that the block holds for every value +generator+ draws
    # against the real engine. A failing value is reported through the
    # failing test case itself, an ordinary Minitest assertion, so Hegel
    # shrinks it to a minimal counterexample before this method raises.
    def assert_all_examples(generator)
      Hegel.test(**QUIET_SETTINGS) do |tc|
        value = tc.draw(generator)
        assert yield(value), "predicate failed for: #{value.inspect}"
      end
    end

    # Asserts that no value +generator+ draws against the real engine
    # satisfies the block.
    def assert_no_examples(generator)
      Hegel.test(**QUIET_SETTINGS) do |tc|
        value = tc.draw(generator)
        refute yield(value), "unexpected example: #{value.inspect}"
      end
    end

    # Finds the minimal value +generator+ draws that satisfies the block
    # (exercises shrinking), spending up to +test_cases+ generation
    # attempts. Ported from hegel-java's Utils#minimal: a case that
    # satisfies the block raises ConditionSatisfied after recording the
    # value, Hegel replays and shrinks it like any other counterexample,
    # and the last (smallest) value that raise recorded is this method's
    # return value.
    #
    # Whether the block was ever satisfied is tracked by +any_found+, a
    # separate flag, not by +found+ being non-nil: nil is itself a value a
    # generator can draw (map { nil } already proves it), so a case that
    # draws nil and satisfies the block must still count as found.
    def minimal(generator, test_cases: 500)
      found = nil
      any_found = false
      begin
        Hegel.test(test_cases: test_cases, **QUIET_SETTINGS) do |tc|
          value = tc.draw(generator)
          if yield(value)
            found = value
            any_found = true
            raise ConditionSatisfied
          end
        end
      rescue ConditionSatisfied
        # Expected: the run raised because a case satisfied the block, and
        # Hegel had already shrunk it to the minimal one by the time this
        # rescue runs.
      end
      assert any_found, "no example satisfied the condition"
      found
    end

    # Finds any value +generator+ draws that satisfies the block. An alias
    # for #minimal (hegel-java's own findAny is exactly
    # `return minimal(gen, condition);`): shrinking a found value down to
    # its minimal form is strictly more informative than stopping at the
    # first one, so there is no separate, non-shrinking path to maintain.
    def find_any(generator, &block)
      minimal(generator, &block)
    end
  end
end
