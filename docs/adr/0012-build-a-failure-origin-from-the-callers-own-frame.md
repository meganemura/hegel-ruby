# 0012 — Build a failure origin from the caller's own frame

## Status

Accepted.

## Context

libhegel groups failures by the origin string a caller passes to
`hegel_mark_complete`. The header is explicit: two failures with identical
origins are the same bug and get shrunk together, and each new origin is a new
bug. So the origin decides both how many failures a run reports and which
failures the shrinker minimises as one.

`Hegel::Runner.origin_for` built that string from the exception's first
backtrace frame. For a `raise` written in the caller's own test body, that is
the right line. For an assertion, it is not, because an assertion library
raises from inside itself. Measured against minitest 5.27.0 and
rspec-expectations 3.13.5:

```
assert_equal 0, 1   ->  Raised at .../minitest-5.27.0/lib/minitest/assertions.rb:176
expect(1).to eq(0)  ->  Raised at .../rspec-support-3.13.7/lib/rspec/support.rb:110
```

Those two lines do not vary. Every failing assertion in a suite produced the
same origin as every other one, whichever property raised it and whichever
line the caller wrote. libhegel therefore saw one bug where there were
several, and shrank them together.

This gem exists to be driven from RSpec and Minitest, so that is not an edge
case; it is the ordinary path.

hegel-rust does not have this problem, and so offers no answer to copy: Rust's
assertion macros expand at the call site, so a panic already carries the
caller's own location. hegel-java does have it, and answers it in
`Runner.originOf` by walking the stack for the first frame that is not
infrastructure, where infrastructure is a list of class-name prefixes — its
own package, JUnit, opentest4j, and the JDK.

## Decision

Build the origin from the first backtrace frame that belongs to neither this
library, nor an installed gem, nor Ruby's own standard library. Keep the
exception's class out of it, as before.

Identifying infrastructure by location rather than by name is where this
departs from hegel-java. A list of framework names needs an entry per
framework, and is wrong by omission the day someone uses a framework nobody
added — silently wrong, in the same way the bug above was silently wrong.
Location answers every framework with one rule, because a test framework is
an installed gem and a caller's own code is not: Bundler loads a `path:` or
`git:` gem from the working copy, not from the gem directory.

When every frame is filtered out, the first frame is used after all. An origin
that is merely coarse still groups consistently, where no origin at all would
lose the failure's identity entirely.

## Consequences

Two failures raised from one line in a caller's own code stay one bug. That is
the intended behaviour, not a residue of this one: a ternary that raises two
different messages is one line and one origin, and splitting it across an
`if`/`else` is what makes it two.

A caller whose code under test is itself an installed gem now gets their own
test line as the origin, rather than the line inside that gem. Two distinct
bugs in one installed dependency therefore group as one if the caller reaches
them from a single line. Distinguishing them is the caller's own to do, by
calling from separate lines, and the shrinker still reports the failure.

The origin string holds an absolute path, so it differs between machines. That
costs nothing: libhegel compares origins only within a single run.
