# Changelog

## [Unreleased]

Nothing is released yet. The version in `lib/hegel/version.rb` stays at `0.0.0`
until the first release to RubyGems.org, which becomes `0.1.0`.

`Hegel.test` runs a property against libhegel, shrinks a failure to its
smallest counterexample, reports the values it drew, and re-raises the
exception the test body itself raised.

Twenty-five generators, composing through `map` and `filter`. A test case can
discard itself with `assume` and `reject`, leave messages with `note`, and
steer generation with `target`. A run can be shaped with `phases`,
`suppress_health_check`, `report_multiple_failures`, `stateful_step_count`,
and libhegel's example database. Stateful testing runs a `Hegel::StateMachine`
and shrinks a failing sequence of rules.

The engine is called through the `ffi` gem. No released gem carries a
`libhegel` build yet, so running this needs a local engine and
`HEGEL_LIBHEGEL_PATH`.

[Unreleased]: https://github.com/meganemura/hegel-ruby/commits/main
