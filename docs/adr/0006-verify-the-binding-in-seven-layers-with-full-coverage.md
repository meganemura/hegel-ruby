# 0006 — Verify the binding in seven layers, with full coverage

## Status

Accepted

## Context

hegel-rust's own `tests/` directory separates concerns.
`tests/test_shrink_quality/` asserts an exact minimal counterexample for a
given predicate; for example, shrinking a byte pair under a length
constraint to `vec![0u8; 7]` and `vec![0u8; 8]`. This kind of assertion
depends on how the engine's shrinker responds to span structure. A missing
or misplaced span shows up there, as a counterexample larger than the
minimal one. hegel-rust's own contributor documentation states that every
invalid combination of builder values must be caught at draw time. It
also states that a validation message is public API, asserted against by
tests as a stable substring.

The Java implementation enforces 100% instruction and branch coverage
through its `jacoco-maven-plugin` configuration, `<minimum>1.00</minimum>`
for both counters. Its `Libhegel` interface exists so the run loop can be
tested against `FakeLibhegel`, without a real engine, exercising every
error code libhegel can return.

## Decision

Verify the binding in seven layers:

1. FFI, against a fake engine.
2. Library resolution.
3. Conformance, running every generator against the real engine.
4. Shrink quality, ported from hegel-rust's `tests/test_shrink_quality`
   result assertions.
5. Generation quality, catching option-translation mistakes.
6. Failure reports: Prism naming, blob replay, output format.
7. Integration, running the Minitest and RSpec suites end to end.

Enforce 100% line and branch coverage in CI, the same bar the Java
implementation's jacoco configuration sets. An excluded file carries a
comment stating why.

## Consequences

A missing or misplaced span costs nothing at generation time. It shows up
as a larger-than-minimal counterexample, the property the shrink-quality
layer asserts against.

Layer two, library resolution, is written and covered. The other six
follow the code they test, so they arrive with it.
