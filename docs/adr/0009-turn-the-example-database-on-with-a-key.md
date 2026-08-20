# 0009: Turn the example database on with a key

## Status

Accepted. It replaces the interim rule that every run disables the example
database, which stood while milestone C was still deciding this.

## Context

libhegel can store a failing test case and replay it first on the next run.
Three settings govern it: `hegel_settings_set_database` chooses a directory
(NULL leaves the default `./.hegel/examples/`, `""` disables storage
entirely), `hegel_settings_set_database_key` scopes what a run stores and
replays, and the engine turns the whole feature off by itself under CI.

Until now every `Hegel.test` call passed `""`, because a run that left the
default in place looked like it would write into a contributor's working
copy and nowhere else. That is the hardest version of that mistake to
notice.

Measurement against 0.32.5 shows the hazard is narrower than that. A run
with the path left at its default and **no key set** wrote nothing at all:
no `./.hegel/`, under that name or any other, in a fresh empty directory,
across two runs of a property that did find and report a failure. The same
run with `hegel_settings_set_database_key(ctx, s, "probe")` produced
`.hegel/examples/` with three hash directories and twenty-nine files, and a
second run in that directory replayed the stored failure as its first and
only test case. A third run with a different key behaved like a fresh
search.

So the key, not the path, is what makes the database do anything.
`hegel_settings_set_database_key`'s own header entry describes NULL as
clearing the key. What a cleared key does to storage is what the measurement
above supplies.

The two implementations that ship this feature both leave the path at the
engine default and get a key from a name they already have: hegel-go passes
Go's own `t.Name()`, and hegel-java passes the `name` its `Settings` carries.
`Hegel.test` has no such name. It is a bare method call, not a named test,
so Ruby has nothing to key a run by unless the caller supplies one.

## Decision

`Hegel.test` gains two keywords.

`database_key:` is the switch. Given a String, the run stores and replays
examples under that key. Left nil, which is the default, the run passes `""`
to `hegel_settings_set_database` and stores nothing.

`database:` chooses the directory, and only means something alongside a key.
Given a String, the run uses that directory. Left nil, a keyed run leaves the
engine's own default in place, which is `./.hegel/examples/` outside CI and
disabled inside it. Given without `database_key:`, it raises `Hegel::Error`
rather than silently storing nothing.

Disabling explicitly rather than relying on the measurement above is
deliberate. "No key means nothing is written" is behaviour this project
measured, not behaviour the ABI promises, and the cost of being wrong is
directories appearing in working copies that never asked for them. Passing
`""` costs one call per run and depends on a documented sentence instead.

CI detection stays the engine's. hegel-go and hegel-java each run their own
check of the same environment variables; here, a run reaching the engine
default in CI is already disabled by the engine, and a run passing an
explicit path means the caller asked for that path.

## Consequences

An unkeyed run behaves exactly as every run behaved before this record, so
the change is invisible to a caller who does not ask for it.

A caller who wants replay writes the key themselves:

```ruby
Hegel.test(database_key: "sorting is idempotent") { |tc| ... }
```

That is more typing than hegel-go or hegel-java need, and the difference is
the name those two already have. A future integration that knows the
enclosing test's name, such as a Minitest or RSpec adapter, can supply the
key from it and close the gap. Nothing here forecloses that, because the
keyword takes any String.

Keying by hand also means two properties can collide by being given the same
key, which a name derived from a test could not do. The header describes the
key as what scopes stored and replayed examples, so two properties sharing a
key share one scope; what the engine then does with a case stored by one and
replayed against the other has not been measured here. The keyword's
documentation says to make the key unique, and this is the reason.
