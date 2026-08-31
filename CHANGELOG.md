# Changelog

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

[0.1.1]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.1
[0.1.0]: https://github.com/meganemura/hegel-ruby/releases/tag/v0.1.0
