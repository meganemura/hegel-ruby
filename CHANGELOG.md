# Changelog

## [Unreleased]

## [0.2.1] - 2026-10-08

Each platform gem carries `libhegel` 0.45.1, up from 0.45.0. A caller has
nothing to change. The engine now reads a NULL string buffer with length
zero as the empty string, and it rejects a NULL buffer with a nonzero
length. These bindings send neither case, so a drawn value does not
change: `from_regex("", fullmatch: true)` draws `""` on both engines.

## [0.2.0] - 2026-10-07

The floor is Ruby 3.4. A project on Ruby 3.3 stays on 0.1.1. See
[ADR 0017](docs/adr/0017-raise-the-ruby-floor-to-3-4.md).

Each platform gem carries `libhegel` 0.45.0, up from 0.32.5. The engine
changed its C interface in several places between the two, and these
bindings follow each change.

### Changes a caller has to make

`Hegel.test` no longer takes `stateful_step_count:`. Pass `step_count:` to
`Hegel::Stateful.run` instead; it defaults to 50, as hegel-rust, hegel-go,
and hegel-java do. The engine no longer has a default of its own.

An invariant no longer runs after every rule. It runs before the first
rule and after the last, and between rules when the engine samples it,
about once in a test case that runs every step. Declare it with
`invariant :name, always_run: true` to keep the check after every rule.
See [ADR 0021](docs/adr/0021-run-a-state-machine-in-rounds-with-its-own-step-count.md).

### Failure reports

The report comes from the engine's own final replay of each failure, which
it runs inside the loop before the run ends. The body is no longer run
again after the run, so a failing run calls it once fewer per failure. A
`tc.note` block runs on each case the engine stamps for capture, which can
be more than one per failure. See
[ADR 0019](docs/adr/0019-report-failures-from-the-cases-the-engine-stamps.md).

A body that fails only some of the time is now reported as an ordinary
failure, with a `note:` line from the engine that says how often it
reproduced. Before, such a body ended the run in `Hegel::Error`. A failure the engine could not confirm comes
without a blob, and its report leaves out the reproduction line.

`reproduce_failure:` now replays its blob as a run, until a replay fails,
within the engine's own budget. A blob from a nondeterministic failure
reproduces this way too. When no replay fails, `Hegel.test` raises
`Hegel::Error` and names both causes: a fixed bug, or a body whose failure
did not recur.

A body that rejects its input with `tc.assume` or `tc.reject` before it
draws anything now raises `Hegel::Error` ("Unsatisfiable"). Before, the
run stopped after that one case and passed.

### Settings

A keyword left `nil` now takes its value from the engine's settings
profile: libhegel's default, a `hegel.toml`, or a `HEGEL_*` environment
variable such as `HEGEL_TEST_CASES`. On a CI server the engine picks its
`ci` profile, which derandomizes the run and turns the example database
off, so a run with `database_key:` and no `database:` stores nothing there.
A keyword you pass still wins. See
[ADR 0023](docs/adr/0023-leave-unset-settings-to-the-engines-profile.md).

### Generated values

The engine draws integers and floats from new distributions, and shrinks
further in several cases, so a seeded run draws different values
than it did on 0.32.5. `from_regex` follows Python's `re` more closely
under `(?i)` and `(?a)`, and its pattern may now hold a NUL character.

`times` and `datetimes` keep microsecond precision. The engine now draws
nanoseconds, and the binding rounds each one down. See
[ADR 0022](docs/adr/0022-keep-microsecond-times-over-a-nanosecond-engine.md).

A `datetimes` bound with a fraction of a microsecond could produce a value
outside it, because only the bound's whole microseconds reached the
engine. The lower bound now rounds up and the upper rounds down.

### Other changes

`HEGEL_LIBHEGEL_PATH` pointing at an engine that lacks a function these
bindings call raises `Hegel::Error` that names the function. Before, FFI
raised a `TypeError` that named nothing.

`rake libhegel:fetch` downloads from hegel-rust's `libhegel-v<version>`
release tags, which hegel-rust uses for engine releases since 0.42.1.

## [0.1.1] - 2026-08-31

The reference that ships inside the gem told a reader to install `hegeltest`
from git and to point `HEGEL_LIBHEGEL_PATH` at a local build. 0.1.0 shipped
that text, and 0.1.0 needs neither. A reader who followed it spent their first
minutes on a checkout and an engine build. The reference now says what the
README says.

A drawn value written inside a larger expression named itself after the
assignment target, so `term_start_date = Date.new(tc.draw(...), 2, 29)`
reported `term_start_date` beside a year. Such a draw now takes the generic
name, and `label:` names it when a name is wanted. See
[ADR 0014](docs/adr/0014-name-a-drawn-value-only-when-the-draw-is-the-whole-assigned-value.md).

The settings table names 100 as libhegel's own default for `test_cases`. The
README shows how to scope `Hegel::Syntax::Methods` to tagged example groups in
a suite that already exists, and how to share a group of draws through a plain
Ruby method. The `text` section says which generators cover the character-set
options it does not take, measured against libhegel 0.32.5.

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

[0.2.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.1
[0.2.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.0
[0.1.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.1
[0.1.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.0
