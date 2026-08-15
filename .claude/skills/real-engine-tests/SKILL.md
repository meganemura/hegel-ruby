---
name: real-engine-tests
description: "Hazards in tests that drive the real libhegel engine, rather than the Fake. Use when writing or debugging a test that calls Hegel.test against the real engine, opens a run through Hegel::LibHegel::Real, or asserts on a failure report -- and when such a test passes for a reason you did not intend."
---

# Tests That Drive the Real Engine

Every rule here was measured against libhegel 0.32.5, each after a test
passed or failed for a reason nobody predicted. None of them is in
`hegel.h`. For generator-specific test shapes, see the `new-generator`
skill instead; this covers what the engine does to a test regardless of
what is being drawn.

## The run stops early if a case has nothing to vary

A test case that discards — `tc.assume(false)`, `tc.reject` — **having drawn
nothing** carries no choices for the engine to vary, so the run is fully
determined after that one trial and reports PASSED. It does not pull
another case.

Draw something before discarding, or the test asserts nothing:

```ruby
body = lambda do |tc|
  calls += 1
  tc.draw_integer(0, 10)   # required, not decoration
  tc.assume(false) if calls <= 2
  raise "boom"
end
```

## `test_cases` is a generation budget, not an iteration count

A run configured for 20 test cases whose body always failed took 1003
iterations; the same run failing conditionally took 109. Never write a
loop, or an assertion, that counts iterations.

The budget counts differently again under filtering. With
`suppress_health_check: [:filter_too_much]`, a property that marks almost
every case INVALID pulled **459** cases against a budget of 50: an INVALID
case does not spend the budget the way a VALID one does. Keep
`test_cases:` small in any test that filters, or the suite slows down for
no added coverage.

## Body calls are cases pulled, plus one replay per failure

`Hegel::Runner.replay_failure` runs the body once more per failure, after
the loop, to record the report's entries and capture the exception to
re-raise. So a run that pulls one case and fails calls the body **twice**.
A test counting body invocations has to add that replay in.

## `verbosity: :quiet` silences the report, not just the engine

It suppresses the failure report this library writes, on top of libhegel's
own progress output. A test that asserts on report text must not pass it
for the run it inspects.

## Read `hegel_run_result` before `hegel_run_free`

Reading it afterwards does not raise. It reports PASSED with zero
failures — a wrong answer that looks like a real one, in a test whose
assertions then pass for the wrong reason.

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
measured this way over ten repetitions per arm: mean first-failure index
40.4 with `hegel_target`, 40.0 without — no difference, on a property
where targeting should have helped.

Assert a deterministic endpoint instead, the way hegel-rust's
`tests/test_targeting.rs` does: draw two integers in `0..1000`, target
their sum over 1000 cases, and assert the maximum observed reaches exactly
2000. Reaching the maximum is what the feature promises; getting there
sooner on average is not something a single run can show.

## Shrinking is what makes a span test bite

A misplaced span does not fail an assertion on the drawn value. It shows
up as a counterexample larger than the minimal one. Assert on the shrunk
value — see the `new-generator` skill's composition test.
