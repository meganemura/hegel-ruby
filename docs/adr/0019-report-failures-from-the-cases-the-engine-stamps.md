# 0019: Report failures from the cases the engine stamps

## Status

Accepted.

## Context

Up to libhegel 0.32.5, a run ended with its failures shrunk, and the
binding built each report itself. After the run, it read each failure's
reproduction blob, rebuilt a test case from it with
`hegel_test_case_from_blob`, and ran the body against that case once more
while it recorded the drawn values.

libhegel 0.44.0 changed both halves. The engine now runs every failure it
reports once more before the run ends, inside the loop the binding drives.
It stamps that case, and a few others, through
`hegel_test_case_should_capture`. The header asks a binding to keep the
output of a stamped failing case under its origin, and to report each
failure from its freshest capture instead of replaying its blob after the
run. A failure can also arrive with no blob: under nondeterministic
handling, an unconfirmed failure has none, and it carries a caveat
(`hegel_failure_caveat`) that quotes the engine's replay evidence.
`hegel_run_start_blob` replays a blob as a run, and the header names it as
the call a reproduce-failure feature should use.

hegel-rust and hegel-java follow this design. hegel-go, hegel-cpp, and
hegel-typescript still replay the blob after the run; each pins an engine
from before 0.44.0, or has not moved its report yet.

## Decision

The runner reads the stamp when each case starts. Only a stamped case
records its draws. A failing case keeps its exception and its entries
under its origin. A newer capture replaces an older one, except that an
unstamped case never replaces a stamped one. hegel-rust ranks its captures
the same way: a newer capture replaces an older one of the same rank or
lower.

After the run, each failure is reported from the capture under its
origin. No blob is replayed.

A failure with no blob is reported without the reproduction line. A
failure with a caveat prints it as a `note:` line after the drawn values,
as hegel-rust does.

`Hegel.test(reproduce_failure:)` starts its run with
`hegel_run_start_blob` and drives it through the same loop. A replay that
never fails raises `Hegel::Error` that names both causes: a fixed bug, or
a nondeterministic body whose failure did not recur.

Keeping the replay after the run was refused. It ran the body once more
per failure on top of the engine's own final replay. It also had no blob
to replay for an unconfirmed failure, so a nondeterministic body would have
raised an internal error in place of a report.

## Consequences

A failing run calls the body once fewer per failure. The cost of naming a
drawn value, a read of the caller's source, falls on the stamped cases
only. Measured against libhegel 0.45.0, a run that calls its body 60 to
80 times stamps 5 of them.

A `tc.note` block runs on every stamped case, which can be more than one
per failure: the engine also stamps the first replays that check a newly
found failure.

`hegel_test_case_from_blob` has no caller left, and its binding is gone.
The sixth layer of verification in ADR 0006 lists "blob replay", which now
means the replay that `hegel_run_start_blob` drives.
