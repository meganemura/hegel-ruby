---
name: hegel-ruby
description: >
  Write property-based tests using Hegel in Ruby projects, with RSpec,
  Minitest, or any other test runner. Use this skill whenever the user asks
  to write tests, add test coverage, or improve testing for Ruby functions,
  modules, or classes — especially when the code has properties like
  round-trips, invariants, or contracts that hold across many inputs. Also
  triggers on: "property-based tests", "PBT", "hegel", "generative tests",
  "randomized testing", "test with random inputs", "shrinking", or when
  existing tests use rantly, prop_check, rubycheck, pbt, or propr.
---

# Hegel: Property-Based Testing for Ruby

This skill covers the Ruby API of Hegel, driven by the `hegeltest` gem (an
unofficial, third-party binding to `libhegel`, unaffiliated with the
`hegeldev` organization). It does not carry Hegel's methodology: how to find
a property worth testing, how to keep a generator from being
over-constrained, and the catalogue of property patterns. That methodology
lives in the upstream
[hegel-skill](https://github.com/hegeldev/hegel-skill), and applies to Ruby
the same way it applies to Rust, Go, C++, TypeScript, Java, and OCaml. Load
that skill first for the workflow and the property catalogue, then come back
here for the Ruby-specific API.

Before writing a Ruby property-based test, load
`references/ruby/reference.md` for the exact API: `Hegel.test`, settings,
`TestCase` methods, every generator and its options, the combinator methods,
and Ruby-specific gotchas.
