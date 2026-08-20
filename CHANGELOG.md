# Changelog

## [0.1.0] - 2026-08-20

The first release.

`Hegel.test` runs a property against libhegel, shrinks a failure to its
smallest counterexample, reports the values it drew, and re-raises the
exception the test body itself raised.

Twenty-five generators, composing through `map` and `filter`. A test case can
discard itself with `assume` and `reject`, leave messages with `note`, and
steer generation with `target`. A run can be shaped with `phases`,
`suppress_health_check`, `report_multiple_failures`, `stateful_step_count`,
and libhegel's example database. Stateful testing runs a `Hegel::StateMachine`
and shrinks a failing sequence of rules.

The engine is called through the `ffi` gem. Each platform gem carries the
matching `libhegel` 0.32.5 build. The platform-independent gem carries none,
so a run on it needs `HEGEL_LIBHEGEL_PATH` pointing at a local build.

[0.1.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.0
