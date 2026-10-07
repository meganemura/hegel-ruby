---
name: real-engine-tests
description: "Hazards in tests that drive the real libhegel engine, rather than the Fake. Use when writing or debugging a test that calls Hegel.test against the real engine, opens a run through Hegel::LibHegel::Real, or asserts on a failure report -- and when such a test passes for a reason you did not intend."
---

# Tests That Drive the Real Engine

Every rule here was first measured against libhegel 0.32.5, each after a
test passed or failed for a reason nobody predicted, and measured again
against 0.45.0. Each one was found by running the engine. For
generator-specific test shapes, see the `new-generator` skill instead; this covers what the engine does to a test regardless of
what is being drawn.

## The run stops early if a case has nothing to vary

A test case that discards, such as with `tc.assume(false)` or `tc.reject`,
**having drawn nothing** carries no choices for the engine to vary, so the
run stops after that one trial. Since libhegel 0.36.6 it fails the run as
Unsatisfiable, which `Hegel.test` raises as `Hegel::Error`; 0.32.5 reported
PASSED instead. It does not pull another case.

Draw something before discarding, or the test never reaches its second case:

```ruby
body = lambda do |tc|
  calls += 1
  tc.draw_integer(0, 10)   # required, not decoration
  tc.assume(false) if calls <= 2
  raise "boom"
end
```

## `test_cases` is a generation budget, not an iteration count

Measured against 0.45.0, a run configured for 20 test cases whose body
failed when a drawn integer passed half its range took 104 to 123
iterations over the runs that failed; one run found no failure and took
exactly 20. Never write a loop, or an assertion, that counts iterations.

The budget counts differently again under filtering. With
`suppress_health_check: [:filter_too_much]`, a property that rejects
almost every case called the body **1040 to 1537** times against a budget
of 20, and 2972 to 3999 against 50: an INVALID case does not spend the
budget the way a VALID one does. Keep `test_cases:` small in any test that
filters, or the suite slows down for no added coverage.

## Body calls are cases pulled, plus the engine's replays of a failure

The engine runs every failure it reports once more before the run ends,
inside the loop, and stamps that case for capture. It also replays a newly
found failure to confirm it. So a run that pulls one case from the
database and fails calls the body **twice**, and an ordinary failing run
calls it more times than it pulled distinct cases. A test counting body
invocations has to add those replays in.

## `verbosity: :quiet` silences the report, not just the engine

It suppresses the failure report this library writes, on top of libhegel's
own progress output. A test that asserts on report text must not pass it
for the run it inspects.

## Read `hegel_run_result` before `hegel_run_free`

Reading it afterwards does not raise. It reports PASSED with zero
failures. That is a wrong answer that looks like a real one, in a test
whose assertions then pass for the wrong reason.

## Point the database at a tmpdir, never `Dir.chdir`

A test that turns the example database on passes an absolute path built
from `Dir.mktmpdir` in `database:`. `Dir.chdir` would reach the engine's
default relative path, and would also change what every other test in the
process sees.

The suite must leave no `.hegel` anywhere. Check with
`find . -name .hegel -not -path './.git/*'` after a full run.

## Do not assert that a search got luckier

Comparing "with the feature" against "without it" and asserting the first
wins is a flaky test wearing a measurement's clothes. Targeting was
measured this way over ten repetitions per arm. Against 0.32.5 the mean
first-failure index was 40.4 with `hegel_target` and 40.0 without; against
0.45.0, failing once the sum reached 1900, it was 109.4 with and 111.8
without. That is no difference, on a property where targeting should have
helped.

Assert a deterministic endpoint instead, the way hegel-rust's
`tests/test_targeting.rs` does: draw two integers in `0..1000`, target
their sum over 1000 cases, and assert the maximum observed reaches exactly
2000. Reaching the maximum is what the feature promises; getting there
sooner on average is not something a single run can show.

## A stateful case runs only some of the rules

`hegel.h` says it directly: each worker enables "a random subset of rules
(at least one per group)", and selection "draws only from that subset".
So a machine with two rules can run a case where one of them never
appears. Measured against 0.45.0 over 200 cases of a two-rule machine:
75 ran only the first rule, 74 only the second, and 51 both.

A test proving that one rule's side effect happened cannot rely on that
rule being in the subset. Give the machine a single rule that branches
internally, rather than two rules where one is the interesting one.

## `(N discarded)` proves where an AssumeFailed went

`Hegel::Runner::GenerationStats` counts a case as discarded only when
`Hegel::AssumeFailed` reaches `Hegel::Runner.classify`. So asserting the
report says `(0 discarded)`, in a body whose only `assume`/`reject` calls
are nested somewhere that is supposed to handle them itself, such as
inside a stateful rule, proves none of them escaped.

That assertion holds structurally, not on average, which makes it worth
reaching for whenever the question is "did this control exception get
caught at the right level".

## Shrinking is what makes a span test bite

A misplaced span does not fail an assertion on the drawn value. It can
show up as a counterexample larger than the minimal one, so assert on the
shrunk value. See the `new-generator` skill's composition test.

Check that the test bites before trusting it. Measured against 0.45.0,
with `start_span` and `stop_span` patched to do nothing, the duplicate-pair
program of arrays of integers still shrank to `[0, 0]` in 14 of 14 runs.
The engine's own shrinker reached the minimal pair without the spans, so
that test does not show span placement on this engine.
