# Changelog

## [Unreleased]

### Engine: libhegel 0.47.1 (was 0.45.13)

The [libhegel 0.47.1 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.47.1)
describe 0.47.1 alone. The
[engine changelog](https://github.com/hegeldev/hegel-rust/blob/libhegel-v0.47.1/hegel-c/CHANGELOG.md)
describes each engine release after 0.45.13, up to 0.47.1.

Each platform gem carries `libhegel` 0.47.1. The engine changes its C
interface: every string is now a `hegel_string_t`, a pointer and a length.
These bindings follow that change. A caller has nothing to change in code.
The engine move changes these results for a caller:

- A run with the default `report_multiple_failures: false` that finds more
  than one distinct failure shrinks only the smallest of them and reports
  it. Before, the engine shrank each failure and then reported one. The
  example database keeps every distinct failure, as found. Such a run calls
  the test body fewer times: for a body with two distinct failures and
  `test_cases: 100`, 73 to 131 calls over 20 seeded runs, where 0.45.13
  made 157 to 202. Both versions reported the same failure in each run.
- A string that holds a NUL character, such as a `target` label or a
  `database:` path, reaches the engine whole. Before, it raised
  `ArgumentError` ("string contains null byte") from the `ffi` gem.

## [0.3.2] - 2026-10-16

### Engine: libhegel 0.45.13 (was 0.45.7)

The [libhegel 0.45.13 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.45.13)
describe 0.45.13 alone. The
[engine changelog](https://github.com/hegeldev/hegel-rust/blob/libhegel-v0.45.13/hegel-c/CHANGELOG.md)
describes each engine release after 0.45.7, up to 0.45.13.

Each platform gem carries `libhegel` 0.45.13. The engine only adds to its C
interface, and these bindings do not use the addition. A caller has nothing
to change in code. The engine changes these results for a caller:

- A run with a `seed:` can draw different values than it did before. The
  engine changed how it copies values between spans that have the same
  label, and how it draws an integer from a range wider than 128 bits.
- A failure that depends on an integer that is a multiple of a number, such
  as 6, shrinks to the smallest such value more often. Before, the shrinker
  could stop at a larger multiple, such as 78.
- A run of 1,000 test cases or more starts to use `target` scores soon
  after it starts. Before, it started after half of the test cases.
- The `note:` line with the engine's nondeterminism caveat shows only for a
  failure that the engine saw pass at least one time. Before, every failure
  of a run that the engine treated as nondeterministic showed it.
- `reproduce_failure:` stops a replay when the test body draws differently
  from the recorded choices. If no replay reproduces the failure, the run
  raises `Hegel::Error` with the message that says that the blob did not
  reproduce a failure, and the engine writes one line to standard error
  that names the position where the draws left the recorded choices.
  Before, the engine continued the replay with new draws and could report a
  different failure as the failure of the blob.

## [0.3.1] - 2026-10-15

### Engine: libhegel 0.45.7 (was 0.45.4)

The [libhegel 0.45.7 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.45.7)
describe 0.45.7 alone. The
[engine changelog](https://github.com/hegeldev/hegel-rust/blob/libhegel-v0.45.7/hegel-c/CHANGELOG.md)
describes each engine release after 0.45.4, up to 0.45.7.

Each platform gem carries `libhegel` 0.45.7. The engine only adds to its C
interface, and these bindings do not use the addition. A caller has nothing
to change in code. The engine changes these messages for a caller:

- `from_regex` with a pattern that no string matches, such as `"(?!)"`,
  raises `Hegel::Error` with a message that names the pattern and says
  that it `matches no string`. Before, the run raised `Hegel::Error` with
  a message that starts with `Unsatisfiable`.
- The FilterTooMuch health check message says how to suppress the check
  with the `suppress_health_check` setting, and it says "rejected by
  assume() or a filter". Before, it showed Rust syntax. The
  `FailedHealthCheck:` and `Unsatisfiable` prefixes do not change.

## [0.3.0] - 2026-10-14

### Engine: libhegel 0.45.4 (was 0.45.1)

The [libhegel 0.45.4 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.45.4)
describe 0.45.4 alone. The
[engine changelog](https://github.com/hegeldev/hegel-rust/blob/libhegel-v0.45.4/hegel-c/CHANGELOG.md)
describes each engine release after 0.45.1, up to 0.45.4.

Each platform gem carries `libhegel` 0.45.4. The engine only adds to its C
interface, and these bindings do not use the additions. The engine
changes these results for a caller:

- A run that generates no valid test case now raises `Hegel::Error` with a
  message that starts with `Unsatisfiable`, also when
  `suppress_health_check:` holds `:filter_too_much` or
  `:test_cases_too_large`. Before, such a run passed. A test that rejects
  every case and expects to pass must now draw at least one valid case.
- `from_regex` records each drawn string as one choice that the pattern
  constrains. A failure shrinks inside the pattern, so
  `from_regex("(?:bbbb|a)", fullmatch: true)` now shrinks to `"a"`, where
  it stopped at `"bbbb"` before. The example database drops a failure that
  an earlier engine saved for a `from_regex` draw, so the first run after
  the update does not replay it.
- `from_regex` rejects a look-behind of variable width, such as
  `(?<=a*)b`, with `Hegel::Error`, as Python's `re` does.
- `\w`, `\d`, `\s`, and case-insensitive matching in `from_regex` follow
  Unicode 17.0. Before, they followed Unicode 15.1.
- A run stops when its test-case budget or its budget of invalid cases is
  spent. Before, it could also stop after ten rejected cases in a row that
  it had seen before.

## [0.2.1] - 2026-10-08

### Engine: libhegel 0.45.1 (was 0.45.0)

The [libhegel 0.45.1 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.45.1)
describe the engine changes.

Each platform gem carries `libhegel` 0.45.1. A caller has nothing to
change. The engine now reads a NULL string buffer with length zero as the
empty string, and it rejects a NULL buffer with a nonzero length. These
bindings send neither case, so a drawn value does not change:
`from_regex("", fullmatch: true)` draws `""` on both engines.

## [0.2.0] - 2026-10-07

### Engine: libhegel 0.45.0 (was 0.32.5)

The [libhegel 0.45.0 release notes](https://github.com/hegeldev/hegel-rust/releases/tag/libhegel-v0.45.0)
describe 0.45.0 alone. The
[engine changelog](https://github.com/hegeldev/hegel-rust/blob/libhegel-v0.45.0/hegel-c/CHANGELOG.md)
describes each engine release after 0.32.5, up to 0.45.0.

Each platform gem carries `libhegel` 0.45.0. The engine changed its C
interface in several places between the two, and these bindings follow
each change. The sections below list what that changes for a caller.

### Ruby

The floor is Ruby 3.4. A project on Ruby 3.3 stays on 0.1.1. See
[ADR 0017](docs/adr/0017-raise-the-ruby-floor-to-3-4.md).

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

[0.3.2]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.2
[0.3.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.1
[0.3.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.0
[0.2.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.1
[0.2.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.0
[0.1.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.1
[0.1.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.0
