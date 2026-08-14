# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.

## What this is

An unofficial Ruby implementation of the [Hegel](https://hegel.dev/) protocol,
published as the `hegeltest` gem. It drives `libhegel`, the native engine that
the official Rust, Go, C++, TypeScript, Java, and OCaml implementations drive.
The engine runs in the same process over a C ABI.

The gem is `hegeltest`, the require path and namespace are `hegel` and `Hegel`.
This mirrors the Rust implementation, whose crate is `hegeltest` and whose
library is `hegel`.

## Project rules

This repository is public. Every commit message, code comment, README, and
document is written in English. Nothing here may carry material from private or
employer contexts.

Design decisions belong in `docs/` as architecture records. A new decision gets
a new record; a changed decision supersedes the old record rather than editing
it, so the history stays readable.

Anything committed must make sense to a reader who has only this repository.
Do not reference working notes, task files, or conversations that a person who
clones the repository cannot read.

## Commands

```bash
bin/setup                      # install dependencies
bundle exec rake               # run the tests and the linter
bundle exec rake test          # run the tests
bundle exec rake standard      # run the linter
bundle exec rake standard:fix  # apply the fixes the linter considers safe
```

`just check`, `just test`, `just lint`, and `just format` call the same Rake
tasks. Rake holds every real definition; each `just` recipe delegates in a
single line, so keep it that way.

## Layout

- `lib/hegel.rb` — the entry point, and the namespace root
- `lib/hegeltest.rb` — a shim that requires `hegel.rb`, so that Bundler's
  automatic require works for a gem named `hegeltest`
- `lib/hegel/` — the library
- `sig/` — RBS signatures
- `test/` — Minitest suite

## Constraints that hold across the codebase

**Only one module touches Fiddle.** Every raw `hegel_*` call goes through the
libhegel binding module. The rest of the library talks to that module's safe
wrappers. The Rust implementation confines its own FFI to `src/ffi.rs` for the
same reason, and the Java implementation puts an interface at that seam so the
runner can be tested against a fake engine. Do the same here.

**Control exceptions inherit from `Exception`, never from `StandardError`.**
A test body that says `rescue => e` would otherwise swallow the library's own
control flow mid-run. This is not theoretical: `Minitest::Assertion` and
`RSpec::Expectations::ExpectationNotMetError` both descend from `Exception`
directly, so the run loop must catch `Exception` and re-raise the library's
control exceptions before doing anything else. `Hegel::Error`, which reports
ordinary failures to the caller, stays a `StandardError`.

**Free native handles deterministically.** Every `hegel_*_free` function takes
the context, so the context must outlive every handle allocated from it.
Finalizer ordering cannot guarantee that. Release handles in an `ensure` block
in the code that owns the run. A finalizer may act as a backstop against leaks,
but it must do nothing when the handle is already free.

**Wrap compound generators in spans.** The engine shrinks better when it can
see the structure of a drawn value. A missing span costs nothing at generation
time and shows up only as a worse counterexample, so the shrink-quality tests
are the layer that catches it.

**The engine is single-threaded.** A context, a run, and a test case each
belong to one thread at a time.

**A generator validates its arguments when it is drawn, not when it is built.**
`integers(min_value: 5, max_value: 1)` returns a generator. The error arrives
from `tc.draw`. hegel-rust states the rule for its own generators: "Every
invalid combination of builder values must be caught at draw time", and its
validation runs at the start of the draw. Follow it, so that a generator means
the same thing in Ruby as it does in every other implementation.

**Validation messages are public API.** hegel-rust says so directly: "These
messages are part of the public API: tests assert against them. Pick a stable,
descriptive substring." Treat a change to one as a change to the interface.

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
- `.agents/skills/` — the project's own procedures. `new-generator` lists the
  test set every generator needs, `coverage` gives the 100% rule and the
  narrow conditions for an exemption, and `self-review` is a pre-review
  checklist.

**The other implementations show how to do it in a language like this one.**
They bind the same engine under constraints Rust does not have.

- **hegel-java** — the closest match on mechanism. Its foreign-function binding
  occupies the same position as Fiddle does here, it manages native handles
  under a garbage collector, and JUnit 5 sits where RSpec and Minitest sit.
- **hegel-typescript** — ships one prebuilt engine per platform-specific
  package, which is the model this gem follows.
- **hegel-go** — how a repository vendors prebuilt engines.
- **hegel-cpp** — a short, direct reading of the C ABI.

When a mechanism reference and hegel-rust disagree about meaning, hegel-rust
wins.
