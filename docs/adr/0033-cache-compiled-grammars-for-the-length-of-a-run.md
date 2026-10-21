# 0033: Cache compiled grammars for the length of a run

## Status

Accepted.

## Context

`from_lark` draws strings of a grammar written in Lark's syntax. The engine
compiles the grammar into a `hegel_grammar_t` with `hegel_grammar_new`,
after a `hegel_grammar_builder_t` has gathered the grammar and every file
its `%import`s name. `hegel.h` calls the compiled grammar immutable, safe to
share across test cases, and freed with `hegel_grammar_free`, which takes the
context. Every draw then reads it through `hegel_generate_grammar`.

Compiling costs far more than drawing. Measured against libhegel 0.47.2 on
x86_64 Linux, compiling `start: INT ("," INT)*` with `%import common.INT`,
which reads the bundled `common.lark`, took about 446 microseconds. With the
grammar already compiled, a test case that drew one string of it, capped at
20 characters, took about 38 microseconds, where a case that drew one integer
took 15. A grammar with no imports compiled in about 46 microseconds.

hegel-rust compiles once per generator: `LarkGenerator` keeps the grammar in
a `OnceLock`, and Rust's `Drop` frees it when the generator goes. Ruby has no
scope exit to hang that free on, and `CLAUDE.md` asks for every native
handle to be freed in an `ensure` in the code that owns the run, before the
context.

## Decision

`Hegel::Runner.run` creates a `Hegel::GrammarCache` inside the context's
block and hands it to every `Hegel::TestCase` of the run, the replay of a
`reproduce_failure:` blob included. An `ensure` frees every grammar in it
after `hegel_run_free` and before `hegel_context_free`. Freeing carries on
past a free that raises and raises the first error once every grammar has
been tried, so one failure does not leave the rest alive when the context
goes.

The cache is keyed by value: the grammar text, the start rule, `max_size`,
`max_depth`, the alphabet's options, the explicit terminal names in order,
and the import path as a string. That is everything the compilation reads.
The explicit generators are not in the key, since only their names reach the
engine. The generator builds the key when it is built, as ADR 0020 asks of a
label, so a draw writes nothing to it. Two generators equal by value share
one grammar, so a `from_lark` built inside the test body compiles once per
run as well.

A compilation that raises stores nothing, and frees what it had built. A
`Hegel::TestCase` built without a cache, as a unit test builds one, compiles
for each draw and frees the grammar after it.

The new-generator skill's rule that a native handle is never cached on the
generator still holds. This cache belongs to the run, and is the route a
handle that is worth keeping across draws takes.

Four alternatives were rejected.

- **Compile on every draw.** `CLAUDE.md` records a run configured for 20
  test cases calling the body up to 1847 times, and an array of grammar
  strings draws once per element. At 446 microseconds a compilation, that
  dominates the run.
- **Cache per test case.** It still compiles once per case, so it saves
  only the draws after the first within one case.
- **Cache on the generator, freed by a finalizer.** `CLAUDE.md` allows a
  finalizer only as a backstop to an `ensure`. The free needs the context
  the grammar came from, which is gone by the time a finalizer runs, and a
  new context can reuse its address. A frozen generator cannot take a cache
  written at draw time either.
- **Cache for the process on a long-lived context.** No code owns that
  context with an `ensure` around it, and the engine's contexts are
  single-threaded, so two threads running properties would share one.

## Consequences

An imported file is read once per run for each key, so a change to it shows
in the next run, not partway through one.

A grammar whose text is built from drawn data gets a new key for each
distinct text, and each stays compiled until the run ends. Such a run holds
one live grammar per distinct text it drew.
