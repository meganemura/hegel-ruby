# Changelog

## [Unreleased]

### Profiles

`Hegel.test` takes `profile:`, the name of a settings profile to start the
run from: a shipped one, one in `hegel.toml`, or one you register. Left
`nil`, the run starts from the default profile as before, and a keyword
passed alongside still beats the profile.

`Hegel::Settings.register_profile(name, profile: nil, **keywords)`
registers a profile for the whole process, and
`Hegel::Settings.set_default_profile(name)` makes a profile the default
for every run; `""` clears it. They follow hegel-rust's
`Settings::register_profile` and `set_default_profile`. An unknown or
reserved name raises `Hegel::Error` with the engine's message. See
[ADR 0028](docs/adr/0028-expose-settings-profiles-as-a-keyword-and-module-functions.md).

### Settings

`Hegel.test` takes five more keywords, with the names and meanings of
hegel-rust's `Settings` methods. Each one left `nil` takes its value from
the engine's settings profile, like `test_cases:` and `seed:`.

- `stop_on_first_failure: false` keeps generating after a failure and
  spends the whole `test_cases` budget before reporting.
- `print_blob: false` leaves the `reproduce_failure:` line out of the
  failure report. Left `nil`, a profile or `HEGEL_PRINT_BLOB` decides.
- `show_statistics: true` makes the engine print, at the end of the run,
  what `tc.event` and `tc.event_value` recorded.
- `nondeterminism_strictness:` takes `:quiet`, `:warn`, or `:error`.
  `:error` ends a run whose test behaves differently on a replay with
  `Hegel::Error`.
- `backend:` takes `:default` or `:urandom`.

### Test location

Every `Hegel.test` run now reports where its test lives to libhegel, with
`hegel_settings_set_test_location`. Under Antithesis the engine writes one
`always` assertion, "<class>::<function> passes properties", for each
location; elsewhere it uses nothing, and no keyword changes. The file is
relative to the working directory when it lies under it, and the class and
function come from the frame that called `Hegel.test`. A call inside a
block takes the name of the method holding the block, and a call outside
any method, such as an RSpec example, takes the file without `.rb` as the
class and `line <n>` as the function, so each example in a file has its
own name.

### Test cases

`tc.event(label)` and `tc.event_value(label, value)` record what a test
reached, for the statistics that `show_statistics: true` prints. They follow
hegel-rust's `TestCase#event` and `TestCase#event_value`.

### Generators

- `date_strings`, `time_strings`, and `datetime_strings` generate ISO 8601
  date, time, and datetime Strings, with no options, as hegel-rust does.
  A time keeps nanoseconds: nine fractional digits appear when the
  nanosecond is not zero.
- `permutations`, `subsequences`, and `samples` draw reorderings, ordered
  subsets, and samples of a given sequence, as hegel-rust does. Its
  `with_replacement` and `without_replacement` setters are one keyword here,
  `samples(replacement: true)`, which is the default.
- `durations(min_value: 0, max_value: 2**64 - 1)` draws a duration as an
  `Integer` count of nanoseconds, as hegel-rust's `durations` does for a
  `Duration`. It follows [ADR 0030](docs/adr/0030-represent-a-duration-as-integer-nanoseconds.md).
- `arrays(elements, unique: true)` draws an array with no two equal entries,
  as hegel-rust's `vecs(...).unique(true)` does. An element equal to one
  already drawn is rejected and drawn again, so `min_size` still counts
  distinct entries.
- `floats(allow_subnormal: nil)` allows or rules out subnormal values, as
  hegel-rust's `allow_subnormal` does. Left `nil`, it allows them whenever
  the bounds admit one. A `floats` call whose bounds admit none, such as
  `floats(min_value: 1.0, max_value: 2.0)`, now tells the engine so.
- `recursive(leaf, max_depth: 32, max_leaves: 100) { |subtrees| ... }`
  draws a recursively defined value, such as a tree, through the engine's
  recursion calls, as hegel-rust's `recursive` does. The engine decides each
  leaf-or-branch choice and owns both budgets. An attempt that outgrows
  `max_leaves` is drawn again from the root, and the spans it opened are
  discarded, not kept. See
  [ADR 0032](docs/adr/0032-suppress-span-closes-while-an-abandoned-recursion-attempt-unwinds.md).

### Text generators

`text` and `characters` take `categories:`, `exclude_categories:`,
`include_characters:`, and `exclude_characters:`, with the names hegel-rust
gives them. `text` also takes `alphabet:`, a `String` of the permitted
characters, and raises `Hegel::Error` at draw
time when it is combined with another character option. `from_regex` takes
`alphabet:`, a `characters` generator that limits every character of the
string, padding included. An unknown `codec:` now raises `"text: invalid
codec: ..."` (or `characters:`) before the engine is called, and a
surrogate category in `categories:` raises too.

### Grammar strings

`from_lark(grammar)` draws strings that a grammar written in the syntax of
the [Lark](https://lark-parser.readthedocs.io/en/stable/grammar.html)
parsing library accepts, as hegel-rust's `from_lark` does. It takes
`start:`, `explicit:` (a `Hash` from terminal name to a generator of the
values drawn for it), `alphabet:` (a `characters` generator),
`max_size:`, `max_depth:`, and `import_path:`. An invalid option raises
`Hegel::Error` at draw time, with hegel-rust's message where it has one.
A grammar is compiled on its first draw in a run and freed when the run
ends.

### Added

- `rule(name, weight: 1.0)` sets how often the engine picks a rule relative to
  the machine's other rules, as `#[rule(weight = w)]` does in hegel-rust. A
  weight that is not finite and positive raises `Hegel::Error` when the machine
  runs. `Hegel::StateMachine.rule_definitions` now maps each name to a
  `Hegel::StateMachine::Rule` with `block` and `weight`, where it mapped to the
  block alone.

### Fixed

- A filter on `Pool#values_consumed` no longer loses the values it rejects. They
  go back into the pool through `hegel_pool_restore` once the draw is over, and
  only the accepted value is consumed, as in hegel-rust.

### Changed

- A filter over a filter now spends 3 attempts between the two predicates, as
  hegel-rust does, where each level used to spend 3 of its own.
- `Hegel::Generator#do_draw_filtered(tc, predicate)` is the draw behind
  `#filter`. A generator whose draws have effects that a rejected value must
  not keep overrides it.

### Repeat a test body

`tc.repeat { ... }` runs its block again and again, for as long as the
engine keeps the loop going, the way hegel-rust's `TestCase::repeat` does.
The engine chooses how many times it runs, and shrinks a failure toward
fewer iterations. Each iteration shows in the failure report as a
`// Repetition #N` line, with what the iteration recorded indented under
it. A `tc.assume` or `tc.reject` inside the block skips that iteration
instead of discarding the whole test case.

The loop does not return when it ends. It raises `Hegel::LoopDone`, which
`Hegel.test` counts as a passing test case. It descends from `Exception`,
like the other control exceptions, so a `rescue => e` in the body does not
catch it. A `break` in the block ends the loop and returns from
`tc.repeat`. See
[ADR 0034](docs/adr/0034-repeat-a-test-body-with-a-ruby-side-indent.md).

## [0.3.4] - 2026-10-20

### Engine: libhegel 0.47.2 (was 0.47.1)

The [libhegel 0.47.2 release notes](https://github.com/hegeldev/hegel/releases/tag/libhegel/0.47.2)
describe 0.47.2. It is the first engine release from the hegeldev/hegel
repository.

Each platform gem carries `libhegel` 0.47.2. The engine does not change its
C interface. A caller has nothing to change in code, and gets the same
results. The engine changes one text: the message of an internal engine
error now gives <https://github.com/hegeldev/hegel/issues> as the place to
report the problem, not the hegel-rust issue tracker.

### Development

- `rake libhegel:fetch` and `rake libhegel:fetch_all` download libhegel
  0.47.2 and later from the hegeldev/hegel releases, and earlier versions
  from the hegeldev/hegel-rust releases.

## [0.3.3] - 2026-10-17

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

[0.3.4]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.4
[0.3.3]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.3
[0.3.2]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.2
[0.3.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.1
[0.3.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.3.0
[0.2.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.1
[0.2.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.2.0
[0.1.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.1
[0.1.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.0
