# 0004 — Expose generators through a mixin, with keyword options

## Status

Accepted

## Context

FactoryBot, a widely used Ruby test-data library, defines a module,
`FactoryBot::Syntax::Methods`, holding methods such as `build` and
`create`. Including it in a test makes those methods callable bare, with
no `FactoryBot.` prefix. The same methods stay reachable through the
module's own namespace for a caller who does not include it.

hegel-rust and the Go implementation expose generators as builder-chain
calls: `gs::integers::<i32>()` in Rust and `hegel.Integers[int](min, max)`
in Go. Each is followed by chained methods, such as `min_size`, for
further options. Neither Rust nor Go has native optional keyword
arguments; Ruby does.

## Decision

Define `Hegel::Syntax::Methods`, a module of generator-constructing
methods (`integers`, `text`, `arrays`, and so on), matching
`FactoryBot::Syntax::Methods` in shape. A caller includes it, in an RSpec
`config.include` or a Minitest test class, to call `integers` and `text`
bare. The same generators stay reachable as `Hegel::Generators.integers`
without the include.

Generator options are keyword arguments, not a builder chain:
`text(min_size: 1, alphabet: "abc")`.

## Consequences

A caller who already uses FactoryBot recognizes the include-a-methods-
module pattern.

A generator with several options reads as one call, such as
`text(min_size: 1, max_size: 20)`, instead of a chain of setter calls.

`Hegel::Syntax::Methods`, `Hegel::Generators`, and every generator remain
to be written; only the naming decision is settled.
