# 0007 — Ship a thin Ruby skill, shaped for donation

## Status

Accepted. The content arrives once milestone A lands a user-facing API.

## Context

The Hegel maintainers publish [hegel-skill](https://github.com/hegeldev/hegel-skill),
a Claude Code plugin that teaches agents to write property-based tests. Its
`skills/hegel/SKILL.md` carries language-agnostic methodology: how to find a
property worth testing, how to keep a generator from being over-constrained,
and a catalogue of property patterns. Step 1 of its workflow reads "load the
corresponding reference from `references/<language>/reference.md`".

That directory holds one subdirectory per language, and the front matter names
the set: Rust, Go, C++, TypeScript, Java, and OCaml. Each language contributes
two files. `reference.md` documents that language's API — setup, test
structure, settings, `TestCase` methods, every generator, the combinator
methods, composite generators, and gotchas. `porting.md` maps another
property-testing library onto Hegel; the TypeScript one covers fast-check,
jsverify, and testcheck-js.

Ruby has its own property-testing libraries. By RubyGems download count they
run rantly, prop_check, rubycheck, pbt, and propr.

Two shapes were available. A self-contained skill would copy hegel-skill's
methodology, which is MIT licensed, so that one install covers everything. A
thin skill carries only the Ruby half.

## Decision

Publish `skills/hegel-ruby/` holding a thin `SKILL.md` alongside
`references/ruby/reference.md` and `references/ruby/porting.md`, written in
the same shape hegel-skill uses for its six languages. The methodology stays
where its authors maintain it.

Write the content when milestone A lands `Hegel.test` and the first
generators, and grow it as each later generator arrives. A reference that
documents an API nobody has built yet records a guess.

Distribute it two ways. The gem already packages `skills/`, the way the
rubydex gem packages its own. A `.claude-plugin/` manifest makes the same
directory installable through the Claude Code marketplace.

## Consequences

Somebody who installs this skill alone gets the Ruby API and reaches
hegel-skill for the methodology. The `SKILL.md` says so.

The two reference files sit in the layout hegel-skill expects, so they can
move upstream unchanged if the Hegel maintainers ever want a Ruby entry.

A generator is finished when its entry in `reference.md` exists, which puts
the documentation next to the code that motivates it rather than at the end
of the milestone.
