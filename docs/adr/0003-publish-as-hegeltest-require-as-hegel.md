# 0003 — Publish as hegeltest, require as hegel

## Status

Accepted

## Context

hegel-rust's `Cargo.toml` names the package `hegeltest` (`[package] name =
"hegeltest"`) and the library `hegel` (`[lib] name = "hegel"`). `cargo add
--dev hegeltest` installs it; source calls `use hegel::...`.

The Go module is `hegel.dev/go/hegel`, imported as package `hegel`. The
npm package is `@hegeldev/hegel`. The Java artifact is `dev.hegel:hegel`.
The OCaml package is `hegel`. In each of these four, the published name
and the code's own name match.

As of 2026-08, neither `hegel` nor `hegeltest` is registered on
RubyGems.org.

## Decision

Publish the gem as `hegeltest`, matching hegel-rust's crate name. Keep the
require path and the namespace `hegel` and `Hegel`, matching hegel-rust's
library name. `lib/hegeltest.rb` exists only to satisfy Bundler's automatic
require, which is derived from the gem name; it requires `hegel.rb` and
defines nothing of its own.

## Consequences

`require "hegel"` is the documented form. `require "hegeltest"` also
works, because Bundler requires a gem automatically under its own name
when the gem is listed in a Gemfile.

The name `hegel` stays free on RubyGems.org for whoever publishes an
official Ruby implementation.

A reader who already knows the Rust implementation's naming pattern can
guess this gem's install name and require path correctly.
