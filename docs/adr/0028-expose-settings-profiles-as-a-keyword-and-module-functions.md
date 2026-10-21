# 0028: Expose settings profiles as a keyword and module functions

## Status

Accepted. Builds on [ADR 0023](0023-leave-unset-settings-to-the-engines-profile.md),
which left the profile to the engine, and applies
[ADR 0015](0015-follow-the-hegeldev-interface-and-take-changes-upstream-first.md).

## Context

libhegel 0.47.2 has three calls for profiles. `hegel_settings_new_for_profile`
builds a settings handle from a named profile. `hegel_settings_register_profile`
stores a complete snapshot of a handle under a name, for the whole process,
replacing an earlier registration of that name. `hegel_set_default_profile`
names the profile that `hegel_settings_new` resolves, for the whole process,
and an empty name clears it. A named profile still extends the default
profile, except `base`. An unknown name, a reserved name, a malformed
`hegel.toml`, and a malformed `HEGEL_*` variable return `HEGEL_E_INVALID_ARG`
with a message. The snapshot leaves out the database key, and a registration
does not change handles that already exist.

hegel-rust exposes them on its `Settings` value: `Settings::from_profile`
and `Settings::try_from_profile` return a `Settings` to adjust with builder
methods, `Settings::register_profile(name, settings)` registers one, and
`Settings::set_default_profile(name)` sets the default. Its documentation
example is `Settings::register_profile("nightly",
Settings::from_profile("ci").test_cases(10_000))`.

Ruby has no `Settings` value. `Hegel.test` takes keywords, and
`Hegel::Settings` is a module of functions that copy those keywords onto a
native handle that exists only for the length of one run (ADR 0023).

## Decision

**`Hegel.test` takes `profile:`, which stands in for `from_profile`.** A
`nil` profile calls `hegel_settings_new`, as before. A String calls
`hegel_settings_new_for_profile`. The keywords apply afterwards in both
cases, so one passed explicitly still beats the profile's value, and the
`reproduce_failure:` path builds its settings the same way. This is a
difference of mechanism under ADR 0015: the value that hegel-rust builds and
then adjusts is, here, the argument of the call that uses it.

**`Hegel::Settings.register_profile(name, profile: nil, **keywords)`
registers a profile.** It sits on `Hegel::Settings` because hegel-rust puts
`register_profile` on `Settings`. It opens a context of its own, builds a
handle from `hegel_settings_new` or from the named `profile:`, applies the
keywords, registers the handle, and frees the handle and then the context in
an `ensure`. It takes an `impl:` keyword, defaulting to `Hegel.default_impl`,
so a test can pass the Fake the way it does to `Hegel.test`.

The keywords are those of `Hegel.test`, each `nil` meaning that no setter
runs, with these exceptions:

- `database_key:` is not accepted. The engine leaves the key out of the
  snapshot, so accepting it would promise something the profile cannot keep.
  Ruby's own `ArgumentError` rejects it, as it does any unknown keyword.
- `database:` goes straight to `hegel_settings_set_database`, a path or `""`
  to turn the database off. The table of ADR 0009 exists to decide what a
  missing key means for a run, and a profile carries no key.
- `report_multiple_failures:` is `nil` by default here, where `Hegel.test`
  defaults it to `false`.

Starting from `hegel_settings_new` matches `Settings::new()`, which resolves
the default profile. hegel-rust's documented example starts from another
profile instead, and `profile: "ci"` is the same thing here.

**`Hegel::Settings.set_default_profile(name)` sets the default profile,**
with the same `impl:` keyword. `""` clears it.

An error from the engine raises `Hegel::Error` with the engine's message,
through `LibHegel.check!`. hegel-rust panics with the same message.

## Consequences

`Hegel.test` always passes `report_multiple_failures`, as ADR 0023 decided,
so a profile's value for it is overridden on every run. A profile can carry
the setting, but it never changes what `Hegel.test` does.

Registrations and the default profile are state of the process, held by the
engine and not by any context. A test that registers a profile leaves it
registered, and the engine has no call to remove one. A test that sets the
default profile clears it again with `set_default_profile("")`. Neither
affects a run that is already in progress.

A `HEGEL_*` variable applies over a profile's snapshot, as the header says
for every handle, so `HEGEL_PRINT_BLOB` beats a `print_blob: false` that the
profile registered. The tests that observe a profile through the failure
report clear those variables first.

Each call to `register_profile` and `set_default_profile` opens and frees a
context. Both are meant for setup, run once, not once per test case.
