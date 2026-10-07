# 0023: Leave unset settings to the engine's profile

## Status

Accepted. Narrows the `nil` rule in the Consequences of
[ADR 0009](0009-turn-the-example-database-on-with-a-key.md).

## Context

A `Hegel.test` keyword left `nil` calls no setter, so the engine's value
applies. Up to libhegel 0.32.5, that value was a fixed default.

libhegel 0.40.0 moved defaults into named profiles that the engine
resolves. `hegel_settings_new` resolves the default profile: one named by
`hegel_set_default_profile`, `HEGEL_DEFAULT_PROFILE`, or a `hegel.toml`;
otherwise `ci` on a CI server and `development` elsewhere. libhegel 0.43.4
then applies `HEGEL_TEST_CASES`, `HEGEL_DATABASE`, `HEGEL_SEED`, and the
other `HEGEL_*` variables on top. The shipped `ci` profile derandomizes the
run, turns the example database off, and suppresses the TooSlow health
check. `hegel_settings_new` can now fail, for a malformed `hegel.toml` or
`HEGEL_*` variable.

hegel-rust builds each run's settings from the reserved `base` profile and
overwrites every field from its own `Settings` value, which it resolved from
the default profile earlier. hegel-go, hegel-cpp, hegel-java, and
hegel-typescript call `hegel_settings_new`.

## Decision

The binding keeps calling `hegel_settings_new` and keeps the `nil` rule.
A keyword left `nil` now takes its value from the resolved profile and the
`HEGEL_*` variables. A keyword the caller passes still wins, because its
setter runs after the engine resolved the profile. A failure of
`hegel_settings_new` raises `Hegel::Error` with the engine's message.

`report_multiple_failures:` still defaults to `false` and is always
passed, so a profile cannot turn a re-raised exception into a count.

Starting from `base` as hegel-rust does was refused. Ruby has no settings
object to resolve a profile into, so the binding would have to read every
field back through the `hegel_settings_get_*` calls to reproduce what
`hegel_settings_new` already does.

## Consequences

A project can shape every run through `hegel.toml` or `HEGEL_*` variables
without changing a call. On a CI server, a run with `database_key:` and no
`database:` stores nothing, because the `ci` profile turns the database
off; passing `database:` turns it back on. A run on CI is derandomized
unless it passes `derandomize: false`.
