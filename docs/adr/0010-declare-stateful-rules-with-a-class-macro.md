# 0010: Declare stateful rules with a class macro

## Status

Accepted.

## Context

A stateful test hands libhegel a list of rule names, then runs whichever rule
the engine picks, step after step, until the engine says the test case's step
budget is spent. The engine owns the choice and the shrinking. What a binding
decides is how its own users write the rules.

The four implementations that ship this each answered in their own language's
terms. hegel-rust's `StateMachine` trait returns `Vec<Rule<Self>>` from
`rules()`, and hegel-cpp does the same from a virtual `rules()`. hegel-go
finds methods by reflection, taking every method whose name begins with `Rule`
or `Invariant`. hegel-ocaml takes rules as a list argument to `Stateful.run`,
each built by `Rule.create ~name ~step`. All four then run the machine from
inside an ordinary test body rather than from a separate entry point.

Ruby has two idioms that fit, and they point at different answers. Minitest
finds tests by their `test_` prefix, which is hegel-go's shape. RSpec, Rake,
and ActiveRecord register work through class-level macros taking blocks, which
is closer to hegel-rust's explicit list. Being Ruby-like does not decide it.

What decides it is what happens to a mistake. Under prefix discovery, a rule
written `rules_push` instead of `rule_push` is not a rule. Nothing raises, the
machine runs with one fewer action, and the test passes: the suite reports
that a behaviour holds when the behaviour was never exercised. hegel-go keeps
that from happening by rejecting a method that takes a `TestCase` without the
prefix. In Ruby the same guard means reading parameter lists to infer intent,
where a declared name raises on the spot.

Writing all three shapes out inside a real Minitest file surfaced a second
difference that the shapes alone did not. Rules want their framework's
assertions. A machine written as its own class reaches neither the generator
methods nor `assert_equal` without saying so, because `Hegel::Syntax::Methods`
was included into `Minitest::Test` and the machine is not one.

## Decision

A machine is a class that inherits `Hegel::StateMachine` and declares its
rules and invariants with class-level macros:

```ruby
class StackMachine < Hegel::StateMachine
  def initialize
    @stack = BoundedStack.new(3)
    @model = []
  end

  rule :push do |tc|
    x = tc.draw(integers(min_value: 0, max_value: 9))
    @stack.push(x)
    @model.push(x) if @model.size < 3
  end

  rule :pop do |tc|
    tc.assume(!@model.empty?)
    raise "pop disagreed" unless @stack.pop == @model.pop
  end

  invariant :size_agrees do
    raise "size disagreed" unless @stack.size == @model.size
  end
end

Hegel.test { |tc| Hegel::Stateful.run(StackMachine.new, tc) }
```

Each block runs against the machine instance, so a rule reads and writes
instance variables like any method. Both macros pass the test case to the
block; an invariant that does not want it declares no parameter, since a Ruby
block ignores arguments it does not name.

`Hegel::StateMachine` includes `Hegel::Syntax::Methods`, so a generator is
callable inside a rule without the machine repeating the include its test
class already has.

Declaring the same name twice in one class raises `Hegel::Error`. A subclass
declaring an inherited name replaces it, the way a redefined method does.
Silently keeping the last of two same-named rules would reintroduce exactly
the disappearing-rule failure this record exists to avoid, while a subclass
overriding one is the ordinary reason to write the name again.

`Hegel::Stateful.run(machine, tc)` runs it from inside an ordinary `Hegel.test`
body, as all four sibling implementations do. Nothing about a stateful test
takes over the run, so a body can draw values before or after running a
machine.

## Consequences

The typo that prefix discovery swallows now raises: `rule :psuh` registers a
rule named `psuh`, the engine picks it, and calling it fails on whatever the
block does. That failure is visible either way. A missing `rule_` prefix, by
contrast, stays silent under prefix discovery.

The machine still has to reach its framework's assertions itself, with
`include Minitest::Assertions` or the RSpec equivalent, and that boilerplate
is real. This library does not include either one for a caller: it takes no
test framework as a dependency, and guessing which one is loaded would make
the base class behave differently depending on load order. A rule can also
just `raise`, which needs nothing, and the examples here do.

Rules registered on a class, rather than found on an instance, means a
machine built some other way has no supported path. That other way could
be rules assembled at run time, or a machine that is not a class. Nothing
here forecloses adding one; the engine only ever receives a list of names
and a way to invoke each, which a later record can decide how else to
supply.
