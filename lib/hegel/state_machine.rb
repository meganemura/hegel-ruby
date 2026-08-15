# frozen_string_literal: true

require_relative "errors"
require_relative "syntax/methods"

module Hegel
  # Base class for a stateful (model-based) test's machine: a subclass
  # declares its actions with the class-level #rule and #invariant macros,
  # then Hegel::Stateful.run drives one instance of it inside an ordinary
  # Hegel.test block. See docs/adr/0010 for the declared shape (a class with
  # macros, not a method-naming convention or an instance-built list) and
  # the reasons behind it.
  #
  # Only declaration lives here. Hegel::Stateful.run owns the loop that
  # calls the declared blocks, the same split hegel-rust draws between its
  # StateMachine trait (rules()/invariants()) and its own free function
  # `run`.
  class StateMachine
    # So a rule or invariant block can call a generator method (integers,
    # arrays, and so on) bare, the same way a Hegel.test block already can
    # via the caller's own include -- see docs/adr/0010's own reasoning for
    # why a machine needs this itself rather than inheriting its test
    # class's.
    include Syntax::Methods

    class << self
      # Declares a rule named +name+: an action the engine may pick to run
      # at any step. +block+ runs via #instance_exec against the machine
      # instance being tested, and is handed the running Hegel::TestCase as
      # its one argument -- ignored if the block declares no parameter, the
      # ordinary Ruby block rule.
      def rule(name, &block)
        declare(:@rules, "rule", name, block)
      end

      # Declares an invariant named +name+, checked once before the first
      # rule runs and again after every rule that completes without its own
      # assumption failing. Same block/argument contract as #rule.
      def invariant(name, &block)
        declare(:@invariants, "invariant", name, block)
      end

      # name => block, in declaration order, this class's own declarations
      # merged over its ancestors'. Hegel::Stateful.run reads this directly
      # to build the ordered rule-name list libhegel indexes by position.
      def rule_definitions
        merged_definitions(:@rules, :rule_definitions)
      end

      # The invariant analogue of #rule_definitions.
      def invariant_definitions
        merged_definitions(:@invariants, :invariant_definitions)
      end

      private

      # Adds +name+ (stringified, so a Symbol and the same-named String
      # collide) to the table at +ivar+, raising Hegel::Error when *this*
      # class already declares one by that name -- the disappearing-rule
      # failure docs/adr/0010 exists to turn into a raise instead. A name
      # only a superclass declared is not a collision here: #declare never
      # reads an ancestor's table, so a subclass re-declaring an inherited
      # name is the ordinary "redefine a method" case the ADR calls out,
      # not this one.
      def declare(ivar, kind, name, block)
        table = instance_variable_get(ivar) || instance_variable_set(ivar, {})
        name = name.to_s
        raise Hegel::Error, "hegel: #{kind} #{name.inspect} is already declared on #{self}" if table.key?(name)

        table[name] = block
      end

      # Shared by #rule_definitions/#invariant_definitions: this class's own
      # table layered over its superclass's already-merged one via
      # Hash#merge, so a name declared on both keeps the position it first
      # held (Hash#merge's own behaviour for a key present in both operands)
      # while every new name from this class is appended -- together, the
      # declaration order the whole ancestor chain built. Recursion stops at
      # the first class that does not respond to +reader+ (Object, past
      # Hegel::StateMachine's own top), rather than comparing against
      # StateMachine directly, so nothing here hard-codes this one class as
      # the root.
      def merged_definitions(ivar, reader)
        inherited = superclass.respond_to?(reader) ? superclass.public_send(reader) : {}
        inherited.merge(instance_variable_get(ivar) || {})
      end
    end
  end
end
