# 0005 — Name drawn values from the caller's source with Prism

## Status

Accepted

## Context

A failure report is more useful when each drawn value has a name, instead
of a position number. hegel-rust's `#[hegel::test]` macro rewrites, at
compile time, `let x = tc.draw(gen)` inside a test function into `let x =
tc.__draw_named(gen, "x", repeatable)`, so the failure report can print
`let x = <value>;`. The Go implementation resolves the caller's source
position at runtime with `runtime.Caller`, then parses that file with
`go/ast` to recover the enclosing statement's text.

Ruby has no macros. Prism, Ruby's parser, ships as a default gem starting
with Ruby 3.3, and can parse a source file into a node tree with source
locations. Parsing `n = tc.draw(gs.integers)` with Prism yields a
`Prism::LocalVariableWriteNode` whose `name` is `:n`.

## Decision

Recover a drawn value's name at runtime, by parsing the caller's source
file with Prism and reading the assignment target at the `draw` call's
location. This mirrors the Go implementation's runtime-parse approach, in
a language without Rust's compile-time macros.

A `label:` argument to `draw` overrides the recovered name. When no name
can be recovered, the value gets a number instead.

## Consequences

Ruby 3.3, the oldest supported Ruby, is also the oldest Ruby that ships
Prism by default. The two floors were chosen together.

No `draw` call, name recovery, or failure report exists in code yet.

How far this recovery reaches into a heredoc, several `draw` calls on one
line, or a method chain has not been checked.
