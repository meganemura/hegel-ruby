# 0022: Keep microsecond times over a nanosecond engine

## Status

Accepted.

## Context

libhegel 0.36.0 changed `hegel_time_t` from a microsecond field to a
nanosecond field, and `hegel_generate_time` and `hegel_generate_datetime`
now draw whole nanoseconds. The struct kept its layout, so a binding that
does not change compiles and binds as before, and then reads nanoseconds as
microseconds.

`times` returns a `"HH:MM:SS.ffffff"` String and `datetimes` a `Time`, each
with microsecond precision. The other implementations disagree on what a
drawn time shows: hegel-rust prints nine digits whenever the nanosecond is
not zero, hegel-typescript prints six digits for a whole microsecond and
nine otherwise, and hegel-cpp truncates to microseconds. hegel-go and
hegel-java return their languages' typed values.

## Decision

`times` and `datetimes` keep microsecond precision. A lower bound's
microsecond becomes its first nanosecond, and an upper bound's its last,
so the engine draws over every nanosecond inside the bounds. The drawn
nanosecond rounds down to a microsecond, so every microsecond in range
stays reachable, both bounds included. The engine does not draw
nanoseconds uniformly, so the microseconds are not equally likely either:
measured against libhegel 0.45.0, two runs of 2000 draws over four
microseconds gave 1437, 284, 162, and 117, and 1428, 296, 153, and 123.

A `datetimes` bound with a fraction of a microsecond narrows to the whole
microseconds inside the range: the lower bound rounds up and the upper
rounds down.

Moving to nanosecond output was refused while the implementations do not
agree on its format. A change to it belongs upstream first, as ADR 0015
requires.

## Consequences

The public format of `times` and the precision of `datetimes` stay as they
were. The binding layer speaks nanoseconds, and the conversion lives in
`Hegel::Generators.first_nanosecond` and `last_nanosecond`.
