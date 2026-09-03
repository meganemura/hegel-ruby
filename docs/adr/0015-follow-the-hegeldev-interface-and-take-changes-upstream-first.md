# 0015: Follow the hegeldev interface, and take changes upstream first

## Status

Accepted.

## Context

This gem is one binding of libhegel among several. The Hegel project
publishes implementations for Rust, Go, C++, TypeScript, Java, and OCaml,
and each one drives the same engine. A person who writes a property in one
language and then writes the same property in another expects the same call
to mean the same thing.

`CLAUDE.md` already names hegel-rust as the authority on meaning: what a
call does, what an error code means, how a value shrinks. That rule settles
disputes about behaviour. It does not say what to do when this gem's public
surface is shaped differently from every other binding while each shape
behaves as documented.

`floats` is that case. Three implementations write the same rule for its
defaults:

- hegel-rust, `src/generators/numeric.rs:315`:
  `allow_nan.unwrap_or(!has_min && !has_max)`, and
  `allow_infinity.unwrap_or(!has_min || !has_max)`
- hegel-go, `primitives.go:136`: the same two expressions, resolved through
  a nil pointer check
- hegel-typescript, `src/generators/numeric.ts:126`: the same two
  expressions, resolved through `??`

This gem instead fixed both to `false`, whatever the bounds. The comment on
`Hegel::Generators::FloatGenerator` carried the reasoning: a caller who
never asks for NaN never has to reason about it, a keyword can be added
later without breaking anyone, and a default flipped from `true` to `false`
would break someone.

That reasoning weighs this gem's own callers. It leaves out what the
difference costs. `floats` with no bounds is the ordinary way to ask for a
double. Under the sibling rule that draw yields NaN and both infinities;
here it yields neither. A property that passes here can fail the moment
somebody ports it to Rust, and the Ruby test was the weaker one all along,
because it never drew the values that break floating-point code. The
difference is invisible at the call site: the same six-word call means two
things.

The skill this repository ships states the difference as a gotcha, so a
reader who finds it is warned. A reader who does not find it gets a green
run and a false conclusion.

## Decision

**The public surface follows the interface the hegeldev implementations
share.** Names, arguments, defaults, and the meaning of each. A feature
that this gem alone has, and a feature that this gem alone lacks, are both
divergences.

**A change to that interface starts as a proposal upstream.** Do not
implement it here first and wait for the others to follow. When a proposal
is accepted, this gem takes the name and the semantics that were settled on,
rather than choosing again.

hegel-rust stays the authority. Where the sibling implementations disagree
with each other, hegel-rust decides, as it already does for behaviour.

Three things stay outside this rule, because they are mechanism rather than
interface. How the engine is reached (the `ffi` gem, ADR 0013). What Ruby
alone can offer a reader, such as recovering a drawn value's name from the
caller's source (ADR 0005, ADR 0014). Where a Ruby hazard forces a
different construction, such as the control exceptions that must inherit
from `Exception`.

This record replaces the reasoning in the comment on
`Hegel::Generators::FloatGenerator`, which decided the same question for
`floats` alone and decided it the other way.

## Consequences

`floats` changes its defaults to the shared rule, and gains the two checks
that come with it: `allow_nan: true` with either bound, and
`allow_infinity: true` with both bounds, each raise `Hegel::Error` at draw
time. hegel-rust and hegel-go both write those checks; the messages here
carry the same substring as theirs.

This breaks callers. A property that draws unbounded `floats` and passes
today will see NaN and infinity after the change, and code that does not
handle them will fail. That failure is the point: the property was not
testing what it appeared to test. A caller who wants the old behaviour
passes `allow_nan: false, allow_infinity: false`, and the call then says
what it does.

Growing the surface gets slower. A generator or an option that would be
useful here has to be worth proposing upstream before it can ship here, and
a proposal can be rejected. The gem trades the speed of deciding alone for
callers who can move between languages.

The comparison has to be made rather than assumed. Adding an option means
reading how the other implementations spell it and what they default it to.
`hegel-rust/src/generators/` holds the generator surface, and hegel-go and
hegel-typescript hold the two closest readings of it for a language with
keyword-style options.
