# 0030: Represent a duration as Integer nanoseconds

## Status

Accepted.

## Context

hegel-rust draws a `std::time::Duration` from `durations()`, by drawing a
`u64` of nanoseconds and converting it. The largest duration it can
generate is `u64::MAX` nanoseconds, about 584 years. `max_value` saturates
at that limit, and a `min_value` above it is a usage error at draw time,
because no generatable value could satisfy it.

Ruby has no duration type in its standard library. The nearest things are
a `Float` count of seconds, which is what `Time#-` and
`Process.clock_gettime` return by default, a `Rational` count of seconds,
and `ActiveSupport::Duration`, which is not part of Ruby. The engine draws
a nanosecond count as an integer, and `integers` already routes a bound
above int64 to `hegel_generate_integer_big`.

## Decision

`durations(min_value: 0, max_value: 2**64 - 1)` returns an `Integer` count
of nanoseconds, drawn through `integers`. Its bounds are nanoseconds too.

An `Integer` is exact over the whole range, where a `Float` of seconds
loses nanoseconds past about 104 days, and a property that compares two
durations stays free of rounding. It composes with
`Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)`, the one
way Ruby reads elapsed time without converting. Under a `Rational` of
seconds a caller needs a conversion before every use as a sleep or a
timeout, and the shrunk value reads as a fraction.

The validation follows hegel-rust. `max_value` saturates at `2**64 - 1`.
A `min_value` above it raises with hegel-rust's wording, and so does
`max_value < min_value`. A negative `min_value` raises as well. Rust's
unsigned type cannot hold one, so its message has no Rust counterpart.

## Consequences

A caller who wants a `Float` of seconds divides by `1_000_000_000.0`. A
change to the unit or the type belongs upstream first, as
[ADR 0015](0015-follow-the-hegeldev-interface-and-take-changes-upstream-first.md)
requires. The unit differs from `times` and `datetimes`, which keep
microseconds, per [ADR 0022](0022-keep-microsecond-times-over-a-nanosecond-engine.md):
those return a formatted String or a `Time`, and a duration is a bare
number with nothing to format.
