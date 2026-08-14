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

## Reference implementations

Read these when a decision needs precedent. They target the same engine.

- **hegel-java** — the closest match. Its foreign-function binding occupies the
  same position as Fiddle does here, it manages native handles under a garbage
  collector, and JUnit 5 sits where RSpec and Minitest sit.
- **hegel-typescript** — the only implementation that ships one prebuilt engine
  per platform-specific package, which is the model this gem follows.
- **hegel-go** — how a repository vendors prebuilt engines.
- **hegel-cpp** — a short, direct reading of the C ABI.
- **hegel-rust** — the source of truth. `hegel-c/include/hegel.h` defines the
  ABI and `src/ffi.rs` shows the intended usage.
