# 0031: Take the alphabet options from hegel-rust

## Status

Accepted.

## Context

`text` and `characters` took `codec:`, `min_codepoint:`, and
`max_codepoint:`, and `from_regex` took no alphabet. hegel-rust's
`text()` and `characters()` also take `categories`, `exclude_categories`,
`include_characters`, and `exclude_characters`. `text()` takes `alphabet`,
and `from_regex()` takes `alphabet`. ADR 0015 makes the shared interface
the target for names, defaults, and meaning.

hegel-rust differs from what a Ruby caller might expect in three places.

- `alphabet` on `text()` is a string of characters, and `alphabet` on
  `from_regex()` is a `characters()` generator.
- When `categories` is given, `exclude_categories` is dropped.
- It rejects the categories `Cs` and `C`, because a Rust string cannot hold
  a surrogate, and it adds `Cs` to the exclusions otherwise. `hegel.h`
  already says that surrogates are always removed from a text generator.

## Decision

The options carry hegel-rust's names and meanings. A `String` alphabet on
`text` is what hegel-rust's `alphabet(&str)` is: no categories, with the
string as `include_characters`. A value that is not a `String` raises at draw
time, since Ruby has no type to make the case unrepresentable. `from_regex`
takes a `characters` generator, as hegel-rust does.

`categories` wins over `exclude_categories`, as in hegel-rust. `Cs` and `C`
are rejected in `categories`. `Cs` is not added to the exclusions, since the
engine removes surrogates itself and a handle is built on every draw.

An unknown codec is rejected in Ruby with hegel-rust's message, at draw time
as ADR 0015 and `CLAUDE.md` require of every validation. The other
constraints that leave no characters are the engine's to report, as in
hegel-rust.

`from_regex` builds its alphabet as a text handle sized 0 to 0, as hegel-rust
does, so an empty alphabet builds and the engine decides whether the pattern
can still match. The handle is built on each draw and freed after the regex
handle made from it, like the handle `text` builds.

## Consequences

An alphabet handle is one more native construction on each `from_regex`
draw. Measured against libhegel 0.47.2 over 5000 draws, `from_regex` took
about 35 microseconds a draw without an alphabet and 47 with one, and
`text(max_size: 5)` took about 31 without categories and 51 with two.
