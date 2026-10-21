# 0032: Suppress span closes while an abandoned recursion attempt unwinds

## Status

Accepted.

## Context

libhegel 0.47.2 draws a recursively defined value, such as a tree, through a
recursion handle: `hegel_new_recursion`, then `hegel_recursion_branch` for
each sub-value, `hegel_recursion_leaf` before each leaf, and
`hegel_recursion_finish` once the root is complete. The engine owns the
branch probabilities and the depth and leaf budgets, so a recursive value is
distributed the same way in every frontend.

An attempt can outgrow its leaf budget. `hegel_recursion_leaf` then answers
`HEGEL_E_RETRY`, and `hegel.h` asks the caller to unwind out of its
generators "without drawing anything further", back to where it called
`hegel_new_recursion`, and to call `hegel_recursion_retry`. The retry closes
the spans the attempt left open and marks them discarded:
`libhegel/src/native/draws/mod.rs` records the span depth when the
recursion starts, and `recursion_retry` stops spans with `discard` set until
the depth is back there. After `RECURSION_MAX_ATTEMPTS`, 9, the retry
answers `HEGEL_E_ASSUME` and the test case is invalid. `hegel_recursion_finish`
can answer `HEGEL_E_RETRY` as well, when the finished value was mispriced;
the engine has then discarded the attempt itself, and the caller draws
again from the root without calling the retry.

hegel-rust unwinds with a panic (`frontends/rust/src/generators/recursive.rs`).
Its `draw_silent` closes a span only when the draw returns, so a panic
sends no `stop_span`, and the spans the attempt opened are still open when
the retry discards them.

Every compound generator in this gem closes its span in `ensure`. An
exception unwinding through them sends `stop_span(discard: false)` for each
span the abandoned attempt opened, and `discard: true` from a `filter`. By
the time the retry runs, those spans are closed and kept, and it finds
nothing above the recursion's depth to discard.

## Decision

`Hegel::TestCase#recursion_leaf` raises `Hegel::LeafBudgetExceeded` when the
leaf answers `HEGEL_E_RETRY`, and the test case keeps that exception until
`#recursion_retry`. While it holds it:

- `#stop_span` makes no native call, so the retry discards the spans the
  attempt opened.
- Every other method that takes the test-case handle raises the same
  exception again before any native call. A body that rescues `Exception`
  and draws on therefore cannot extend an attempt the engine is about to
  discard.
- A call that takes only the context still runs: `collection_free`,
  `string_generator_free`, and `recursion_free`. hegel-rust's `Drop` runs the
  same frees while its panic unwinds.

`LeafBudgetExceeded` descends from `Exception`, as `Hegel::StopTest` does,
and carries the recursion it belongs to. `RecursiveGenerator` rescues only
its own, so one raised in an outer recursive draw passes through an inner
one. After each attempt the generator asks the test case whether that
attempt was abandoned, rather than relying on having rescued the exception.
A body that swallowed it and returned a value is caught the same way, and
the value, built from draws the engine is about to discard, is dropped.

`#recursion_retry` reaches the engine with the raw handle. `HEGEL_OK` clears
the held exception. `HEGEL_E_ASSUME` or `HEGEL_E_STOP_TEST` ends the test
case, and its exception takes the held one's place, so a later call raises
that verdict without reaching the engine. hegel-rust's data source
short-circuits the same way once a test case is aborted
(`libhegel/src/native/data_source.rs`).

The held exception can reach the run loop only when something replaced it
mid-unwind, such as an `ensure` that raised, and the body rescued that and
drew again. `Hegel::Runner.classify` then marks the case INVALID. It is the
library's own control flow, and its attempt never reached the retry, so it
is not reported as a counterexample.

A subtree generator drawn after the recursive draw that made it has ended
raises `Hegel::Error`, since its recursion handle is already freed.

## Alternatives rejected

- **Roll the span depth back after `ensure` has closed the spans.** The
  closes have already reached the engine as kept spans, and the ABI has no
  call that reopens a span or marks a closed one discarded.
- **Close spans only when a draw returns, as hegel-rust does.** That changes
  every exception path through every compound generator: a failed
  assumption, an overrun, a failing assertion, and the span handling of a
  stateful rule, which is written around closing in `ensure`.
- **Let draws return made-up values while the attempt is abandoned.** The
  caller's code would run on values the engine never drew, could fail or
  loop on them, and the header says to draw nothing further.
- **Unwind with `throw` and `catch`.** `throw` passes a `rescue Exception`
  by, but it runs `ensure` blocks just as an exception does, so the span
  closes still have to be suppressed. CLAUDE.md requires the library's
  control flow to use exceptions descending from `Exception`, and with the
  held exception in place a swallowed unwind cannot reach the engine anyway,
  so `throw` adds nothing.

## Spans

hegel-rust draws each leaf and each branch generator through `draw_silent`,
which wraps it in a span labelled with that generator's label. This gem
opens a span only around a generator that makes more than one native call
itself (ADR 0020 and the `new-generator` skill), so the leaf and branch
spans were settled by measurement. Against libhegel 0.47.2, six
shrink-quality tests ported from `frontends/rust/tests/test_recursive.rs`
(shrink to a leaf, the minimal empty branch, the minimal binary branch, the
deep witness hoisted to the root at `max_depth` 3, the rare one at
`max_depth` 4, and the saturated budget) each shrank to the expected value
in 10 of 10 runs both with those spans and without them. The draw opens
neither.

The spans that remain are the recursive generator's own span, and a span
around every non-root subtree, all labelled with the recursive generator's
label. hegel-rust gives every depth that label so the shrinker can replace a
tree with one of its subtrees. `tuples` here opens no span per element, so
without the subtree's own span a subtree inside a `tuples` branch would
carry no span with that label. Under `arrays` the element span and the
subtree span nest with the same label.

None of the six tests shows these spans doing their job on this engine.
With the subtree span removed, with subtrees labelled apart from the
recursive generator, with the recursive generator's own span removed, and
with every `start_span` and `stop_span` in the library made a no-op, each
test still passed 10 of 10. Over eight seeded runs of the rare deep witness,
the number of test-body calls stayed within 3% of the same total
(14,488 to 14,899) across all of those variants. The span tests against the
Fake pin where the spans go, as they do for the other compound generators.

## Consequences

An attempt that outgrows its leaf budget costs one raised exception and its
backtrace, and the engine allows at most 9 attempts per draw. Each call
that takes the test-case handle checks one instance variable first.

Against libhegel 0.47.2, the port of hegel-rust's large-tree test, a tree of
`arrays` branches shrunk to exactly 30 leaves, called the body about 17,000
to 19,500 times and took 30 to 40 seconds. Each draw made about 240 native
calls, about 100 of them span opens and closes, and the time inside the
engine was about a quarter of the total.

The real-engine tests of `recursive` live in
`test/hegel/test_recursive_engine.rb`, which `rake mutation` leaves out.
With them in, the file took longer than mutineer's 10-second limit for one
mutant, and 16 of the mutants on the new lines timed out without a verdict.
The tests against the Fake, in `test/hegel/test_recursive.rb`, pin the
generator's calls exactly and stay in the mutation run.
