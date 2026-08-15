# 0008 — Revisit the binding after milestone C, on measurement

## Status

Accepted, and carried out.
[ADR 0013](0013-bind-libhegel-through-the-ffi-gem.md)
records the measurement this scheduled and the decision it produced.

## Context

[ADR 0001](0001-bind-libhegel-through-fiddle.md) chose Fiddle over the `ffi`
gem, on the reading that Fiddle adds no third-party runtime dependency while
both avoid a compiler at install time. Building against it has since produced
evidence that decision could not have had.

**Fiddle has no struct-by-value argument.** `Fiddle::Function` converts each
argument type with `NUM2INT`, so a struct type cannot be expressed. Three ABI
draws take their bounds that way. They are reached by packing an eight-byte
all-integer struct into the register the ABI would have used for it, which is
sound for those three and is not a general technique: it puts the ABI
classification in this gem's own code, duplicates field offsets by hand,
cannot follow a struct holding a float, cannot express a struct return, and
diverges on Win64 for the sixteen-byte case. `ffi` has `FFI::Struct.by_value`
and lets libffi classify.

**Fiddle::Closure is still unverified here.** The engine's output callback is
passed as NULL, which the ABI documents as leaving output on stderr, so
nothing depends on the closure yet. Wiring the callback would put weight on a
Fiddle feature this project has never exercised across the fiddle versions
Ruby 3.3 through 4.0 ship.

**Ruby implementations.** `ffi` runs on JRuby and TruffleRuby; the Fiddle
choice scoped this gem to CRuby.

Against that: `ffi` is a runtime dependency, and this project's dependency
rule asks for a reason and an explicit decision before one is added.

None of the above is about speed, and speed is what a property-based testing
library spends. A run configured for twenty test cases was measured making
over a thousand iterations while shrinking, each with its own draws, so the
per-call cost of the binding is multiplied by a large and unpredictable
factor.

## Decision

Measure the two bindings against each other once milestone C is complete, and
choose on the result.

Measure a realistic property run, not a microbenchmark: a failing property
over `arrays(integers)` that shrinks, which is the shape that multiplies
per-call cost, plus a passing run of the same size for the no-shrink case.
Report wall-clock for each binding on the same machine, same engine build,
same seed, with the database disabled.

Library load time is measured too and reported separately. It happens once
per process and should not be added to the per-call figure.

A difference that shows on that run decides it. A difference visible only in
a tight loop around one native call does not: this gem's callers pay the
former and never the latter.

Milestone C is the trigger because it adds the last of the binding surface —
the example database, targeted testing, stateful testing, pools — so a
measurement taken before it would cover a fraction of the calls and a
rewrite after it would be smaller than one before.

## Consequences

The binding stays Fiddle through milestones B and C, and the packing
technique carries the three struct-taking draws until then.

A switch stays cheap because of the seam: `Hegel::LibHegel::Real` is the only
file that names Fiddle, and a conformance test already holds both it and the
Fake to one method list. The cost is that file, the gemspec, and this record's
supersession — not the twenty-odd files built on top.

If the measurement favours `ffi`, adding it is still a dependency decision
under this project's own rule, and the reason recorded here is the argument
that decision would weigh: not `ffi` alone, but `ffi` together with
struct-by-value, an exercised closure, and JRuby and TruffleRuby.
