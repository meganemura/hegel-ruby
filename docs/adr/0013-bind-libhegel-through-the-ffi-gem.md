# 0013 — Bind libhegel through the ffi gem

## Status

Accepted. Supersedes
[ADR 0001](0001-bind-libhegel-through-fiddle.md), and carries out the
measurement [ADR 0008](0008-revisit-the-binding-after-milestone-c-on-measurement.md)
scheduled for the end of milestone C.

## Context

ADR 0001 chose Fiddle over the `ffi` gem, on two grounds: Fiddle ships with
Ruby, so it adds no third-party runtime dependency, and neither one needs a
compiler at install time. ADR 0008 then recorded three things building against
Fiddle had since shown — no struct-by-value argument, an unexercised
`Fiddle::Closure`, and no JRuby or TruffleRuby — and scheduled a measurement
rather than deciding on them, because none of those is about speed, and speed
is what a property-based testing library spends.

The whole binding surface exists now, so the measurement ran. An `ffi`
implementation of `Hegel::LibHegel` was written for the calls a failing
`arrays(integers)` property reaches, and checked against the Fiddle one before
anything was timed: same property, same seed, both bindings. The body call
count, every drawn value, the raised message, the failure report, and the
reproduction blob all matched. The two answer identically, so their times are
comparable.

Measured on Ruby 4.0.6, arm64-darwin, libhegel 0.32.5, `test_cases: 500`, same
seed, twelve reps, minimum of each:

| property | fiddle | ffi | ratio |
|---|---|---|---|
| 800-element fixed-length array, shrinking | 2140 ms | 727 ms | 2.9x |
| plain `arrays(integers)`, passing | 17.6 ms | 6.6 ms | 2.7x |
| plain `arrays(integers)`, shrinking | 3.4 ms | 2.0 ms | 1.7x |

The ratio varies with how many native calls a property makes per case, which
is what the first row exaggerates on purpose and the other two do not. The
direction does not vary. ADR 0008 asked for a difference visible on a
realistic property run rather than in a tight loop around one call, and 1.7x
to 2.9x on whole-run wall clock is that.

Two of ADR 0008's three non-speed items settled the same way. `FFI::Struct`
with `.by_value` expresses `hegel_date_t`, `hegel_time_t`, and
`hegel_datetime_t` directly, and a degenerate draw with every field distinct
round-tripped exactly for all three — where the Fiddle binding packs those
structs into integer registers by hand, and its sixteen-byte case has stayed
unverified on Win64, since that ABI passes anything over eight bytes by
reference. An `FFI::Function` connected to `hegel_run_start`'s output
callback, the run completed, and six lines of engine output arrived in Ruby;
the Fiddle binding passes NULL there and has never exercised
`Fiddle::Closure`.

The third, JRuby and TruffleRuby, was not measured: neither is installed here.
`ffi` publishes a `java` platform build, and this remains a claim about
packaging rather than something this project has run.

Against all of that, `ffi` is a third-party runtime dependency. Two facts
narrow the gap ADR 0001 saw. Fiddle became a bundled gem rather than a default
one, so `hegeltest.gemspec` already declares `fiddle` as a dependency — the
change is which binding gem is declared, not whether one is. And `ffi` 1.17.4
publishes precompiled binary gems for every platform this gem targets:
`x86_64-linux-gnu`, `aarch64-linux-gnu`, both `-musl` variants, `arm64-darwin`,
`x86_64-darwin`, `x64-mingw-ucrt`, `aarch64-mingw-ucrt`, and `java`. Installing
still needs no compiler.

## Decision

Bind libhegel through the `ffi` gem. `Hegel::LibHegel::Real` is written
against `ffi` alone, with nothing left over from the Fiddle binding: the
hand-packed date, time, and datetime structs become `FFI::Struct` definitions
passed by value, and the tests that pinned those packings by field offset go
with them, because `ffi` is what computes the layout now.

Every raw binding call stays confined to that one file, as ADR 0001 decided
and this record keeps. That confinement is why this switch costs one file
rather than twenty: the conformance test holds `Real` and the Fake to a single
method list, and every other file in the library talks to that list.

The gemspec declares `ffi` with a pessimistic constraint, and `Gemfile.lock`
pins the exact version, matching how this project already handles a
dependency.

## Consequences

The struct-by-value entry in this project's open questions closes. There is no
longer a hand-computed field offset to drift from the header, and no Win64
divergence to confirm, because libffi classifies the argument.

The `Fiddle::Closure` open question closes too, by no longer being about
anything: nothing in this library uses Fiddle. Wiring the engine's output
callback is now possible rather than merely plausible, though this record does
not wire it — output stays on stderr until something asks for it.

`ffi` reaches JRuby and TruffleRuby where Fiddle did not. That widening is
untested here, and naming it in a release note before someone has run the
suite on either would claim more than has been shown.

A caller now installs a gem with a native component. `ffi` publishes builds
for the platforms above, so the ordinary install compiles nothing; a platform
outside that list falls back to compiling `ffi` from source, which the Fiddle
binding never asked of anyone.
