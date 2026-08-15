# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.

## Overview

An unofficial Ruby implementation of the [Hegel](https://hegel.dev/) protocol,
published as the `hegeltest` gem. It drives `libhegel`, the native engine that
the official Rust, Go, C++, TypeScript, Java, and OCaml implementations drive.
The engine runs in the same process, over a C ABI, through the `ffi` gem.

The gem is `hegeltest`, the require path and namespace are `hegel` and `Hegel`.
This mirrors the Rust implementation, whose crate is `hegeltest` and whose
library is `hegel`.

## Project rules

This repository is written for publication, and is private only until the work
is ready to show. Write every commit message, code comment, README, and
document in English, and write each one as though it were already public,
because rewriting history later is the expensive way to find out something
should not have been committed. Nothing here may carry material from private
or employer contexts.

Anything committed must make sense to a reader who has only this repository. Do
not reference working notes, task files, or conversations that a person who
clones the repository cannot read. When you want to cite one, write the
substance in place instead.

Design decisions belong in `docs/` as architecture records. A new decision gets
a new record; a changed decision supersedes the old record rather than editing
it, so the history stays readable.

Write comments that record why: a constraint, or an alternative that got
rejected. The code already states what it does. Reading another repository's
agent instructions does not change this one: hegel-rust, for example, asks its
own agents for almost no comments, and that instruction applies where it
lives.

Do not write a claim that rests on absence: "only here", "nothing else does
this", "no other implementation states it". A search reports where something
is, and never reports that you found all of it. Write the positive relation
instead, and name the file that carries it.

## Build and test commands

```bash
bin/setup                      # install dependencies
bundle exec rake               # run the tests and the linter
bundle exec rake test          # run the tests
bundle exec rake standard      # run the linter
bundle exec rake standard:fix  # apply the fixes the linter considers safe
```

`just check`, `just test`, `just lint`, and `just format` call the same Rake
tasks. Rake holds every real definition, and each `just` recipe delegates in a
single line. Keep it that way, so the two entry points cannot drift.

## Layout

- `lib/hegel.rb` — the entry point, and the namespace root
- `lib/hegeltest.rb` — a shim that requires `hegel.rb`, so that Bundler's
  automatic require works for a gem named `hegeltest`
- `lib/hegel/` — the library
- `sig/` — RBS signatures
- `test/` — Minitest suite
- `docs/` — architecture and decision records

## Architecture

### How a run works

Ruby drives the loop. `hegel_run_start` starts the engine's run; Ruby pulls
test cases off it with `hegel_next_test_case`, runs the user's block against
each test-case handle, and reports each outcome with `hegel_mark_complete`.
Generation, targeting, shrinking, database replay, and the final replay all
happen inside the engine. Because Ruby owns the loop, an exception raised by a
user's test body never crosses into native code.

### Standing constraints

These shape code as you write it, so they live here rather than in a skill.

**Only one module touches `ffi`.** Every raw `hegel_*` call goes through the
libhegel binding module, and the rest of the library talks to that module's safe
wrappers. hegel-rust confines its own FFI to `src/ffi.rs`, and hegel-java puts
an interface at that seam so the runner can run against a fake engine. Do the
same here.

**Control exceptions inherit from `Exception`, never from `StandardError`.** A
test body that says `rescue => e` would otherwise swallow the library's own
control flow mid-run. `Minitest::Assertion` and
`RSpec::Expectations::ExpectationNotMetError` both descend from `Exception`
directly, so the run loop must catch `Exception` and re-raise the library's
control exceptions before doing anything else. `Hegel::Error`, which reports
ordinary failures to the caller, stays a `StandardError`.

**`rescue Exception` must let four classes straight through.** `Interrupt`,
`SignalException`, `SystemExit`, and `NoMemoryError` say that the process is
ending, not that a property failed. Catching one turns Ctrl-C into a
counterexample, and the engine then spends its shrink budget minimising an
interrupt. Re-raise them first, ahead of the library's own control exceptions.
No sibling implementation shows this, because Rust's `catch_unwind` sees
panics alone; it is a Ruby-only hazard.

**A finished test case reports one of four outcomes.** `hegel_mark_complete`
takes VALID when the body returned, INVALID when a precondition rejected the
case, OVERRUN when the engine ran out of choices, and INTERESTING when the
body raised anything else. There is no separate "the test itself broke"
outcome: every non-control exception is a counterexample. A run-level error —
a failed health check, a nondeterministic body — is the engine's own verdict,
read from `hegel_run_result_status` afterwards.

**An origin string groups failures, so it must be stable.** `mark_complete`
takes one alongside INTERESTING. The ABI documentation is explicit: "Two
failures with identical origins are the same bug and get shrunk together. Each
new origin is a new bug." Build it from the first backtrace frame that is the
caller's own — skipping this library, installed gems, and the standard library
— so that an assertion counts as failing where the caller wrote it rather than
inside the framework that raised. See
[ADR 0012](docs/adr/0012-build-a-failure-origin-from-the-callers-own-frame.md).

**The test-case setting bounds generation, not the number of times the loop
runs.** Shrinking draws more cases on top of it. Measured against libhegel
0.32.5, a run configured for 20 test cases whose body always failed on a drawn
integer yielded 1003 cases; the same run failing conditionally yielded 109.
Two things follow. Drive the loop until `hegel_next_test_case` hands back
nothing, never by counting. And keep per-case work cheap: anything expensive
enough to notice — reading source to name a drawn value, formatting a
backtrace — belongs in the single final replay rather than in every shrink
probe. hegel-rust reaches the same conclusion from the other side, calling
backtrace capture "the dominant cost of failing-heavy property runs".

**Free native handles deterministically.** Every `hegel_*_free` function takes
the context, so the context must outlive every handle allocated from it.
Finalizer ordering cannot guarantee that. Release handles in an `ensure` block
in the code that owns the run. A finalizer may back that up against leaks, but
it must do nothing when the handle is already free.

**Wrap compound generators in spans.** The engine shrinks better when it can
see the structure of a drawn value. A missing span costs nothing at generation
time and shows up only as a worse counterexample, so the shrink-quality tests
are the layer that catches it.

**A generator validates its arguments when it is drawn, not when it is built.**
`integers(min_value: 5, max_value: 1)` returns a generator, and the error
arrives from `tc.draw`. hegel-rust states the rule for its own generators:
"Every invalid combination of builder values must be caught at draw time", and
runs the check at the start of the draw. Follow it, so that a generator means
the same thing in Ruby as it does everywhere else.

**Validation messages are public API.** hegel-rust says so directly: "These
messages are part of the public API: tests assert against them. Pick a stable,
descriptive substring." Treat a change to one as a change to the interface.

**A run without a `database_key` disables the example database explicitly.**
`hegel_settings_set_database_key` is the switch; `hegel_settings_set_database`
only chooses a directory, defaulting to `./.hegel/examples/`. Measured against
0.32.5, a run with no key wrote nothing even with that default path in place —
but that is a measurement, not a promise the header makes, and being wrong
about it puts a directory in a contributor's working copy and nowhere else,
which is the hardest version of this to notice. So an unkeyed run passes `""`.
See [ADR 0009](docs/adr/0009-turn-the-example-database-on-with-a-key.md).

**A test that opens a real run either leaves the database off or points it at
a temporary directory.** The suite must leave no `.hegel` behind, and
`Dir.mktmpdir` with an absolute path in `database:` gets there without
`Dir.chdir`, which a test cannot do without changing what every other test
sees.

**The engine is single-threaded.** A context, a run, and a test case each
belong to one thread at a time.

## Key patterns

### Code coverage

This project requires 100% line coverage. An excluded line needs a written
reason and explicit human permission; reach for a test, then a refactor, and
only then an exclusion. See the `coverage` skill for the full approach and for
what to do when a line will not cover.

### Before you call the work done

See the `self-review` skill. It runs the checks, reads the diff, and confirms
the standing constraints above.

### Adding a generator

See the `new-generator` skill: the validation and span pattern distilled from
`IntegerGenerator`, `ArrayGenerator`, and `TextGenerator`, plus the required
test set for each new generator.

### Testing against the real engine

See the `real-engine-tests` skill. It collects what the engine does to a test
regardless of what is drawn — why a case that discards without drawing ends
the run, why counting iterations is wrong, and which mistakes make a test pass
for a reason nobody intended.

## Where the answers come from

**hegel-rust defines what is correct.** libhegel lives inside it, as the
`hegel-c` member of the same Cargo workspace. Every question about meaning
answers there: what a call does, what an error code means, who owns what, what
a span changes, how a value shrinks, what a generator option constrains.

- `hegel-c/include/hegel.h` — the ABI
- `src/ffi.rs` — the safe wrappers the ABI is meant to get, one per handle
- `src/run_lifecycle.rs` — the per-test-case lifecycle
- `tests/` — the behaviour a binding must reproduce, including
  `tests/test_shrink_quality/`
- `.agents/skills/` — that project's own procedures

**The other implementations show how to do this in a language like Ruby.** They
bind the same engine under constraints Rust does not have.

- **hegel-java** — the closest match on mechanism. Its foreign-function binding
  occupies the same position as `ffi` does here, it manages native handles
  under a garbage collector, and JUnit 5 sits where RSpec and Minitest sit.
- **hegel-typescript** — ships one prebuilt engine per platform-specific
  package, which is the model this gem follows.
- **hegel-go** — how a repository vendors prebuilt engines.
- **hegel-cpp** — a short, direct reading of the C ABI.

When a mechanism reference and hegel-rust disagree about meaning, hegel-rust
wins.
