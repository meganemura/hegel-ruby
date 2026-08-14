---
name: coverage
description: "How to approach code coverage in this project. Use when the coverage check fails, when writing tests for new code, when deciding whether to exclude a line, or when code seems untestable. Use it proactively while writing new code, so that the code comes out coverable."
---

# Code Coverage

This project requires 100% line coverage and 100% branch coverage. An excluded
line needs a written reason and explicit human permission.

## Why the bar sits at 100%

Every implementation of Hegel that binds the native engine holds itself to this
bar. hegel-go sets `file: 100` in `.testcoverage.yml`. hegel-typescript sets
lines, branches, functions, and statements to 100 in `vitest.config.ts`.
hegel-rust states the rule in its own coverage skill and enforces it with a
ratchet.

The bar earns its keep here for a specific reason. This library is a binding.
A branch nobody runs is a branch where a C call gets the wrong argument, a
handle never gets freed, or an error code maps to the wrong exception. Those
faults produce no symptom until somebody's test suite behaves strangely, so the
coverage check is the thing that finds them.

## Exclusions are not a budget

Reach for a test first, then a refactor, then an exclusion. An exclusion is the
last option, not the cheap one.

Ask before adding one. When permission is given, mark it and write the reason
next to it:

```ruby
# :nocov:
# Reachable only when the platform reports an OS that RbConfig cannot name.
# No supported runner produces it, and faking RbConfig here would test the
# fake instead of the code.
raise Error, "..."
# :nocov:
```

An exclusion without a reason beside it is a defect. A reader cannot tell an
accepted gap from a forgotten one.

## Write tests that could fail

A test that passes after you break the code tests nothing. Before writing one,
name the bug it would catch.

- **Check against an independent source.** When the right answer is available
  another way, compare against that way. For a generator, the engine's own
  behaviour under hegel-rust's tests is such a source.
- **Separate the seam from the subject.** The library binding module has a real
  implementation and a fake. Drive the error paths through the fake, so that
  every error code gets exercised without a native library present.
- **Inject what you cannot control.** Resolution takes the environment and the
  host as arguments rather than reading them directly, which is what makes its
  branches reachable from a test.

## When a line will not cover

Work through these in order.

1. **It just needs a test.** Assume this first. Most uncovered lines are
   ordinary code that nobody got to yet.
2. **It needs a seam.** The code reads global state, touches the filesystem, or
   calls a native function directly. Pass the dependency in instead. This is a
   design improvement that coverage happened to reveal.
3. **It is unreachable.** Delete it.

## Running the check

`bundle exec rake coverage` runs the test suite with `COVERAGE=1` set, then
enforces the 100% line and branch minimum. `bundle exec rake` (the default
task) runs `coverage` and `standard` together, the same as CI.

Coverage stays off by default so a single test file can still run on its own
(`bundle exec ruby -Itest -Ilib test/hegel/test_locate.rb`, for example)
without tripping the 100% minimum on a partial run. `bundle exec rake test`
runs the suite this way, with no coverage measurement, for a fast local loop.
