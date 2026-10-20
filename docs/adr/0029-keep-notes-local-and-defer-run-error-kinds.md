# 0029: Keep notes local, and defer run error kinds

## Status

Accepted. It records two calls that libhegel 0.47.2 offers and this gem does
not bind into its public surface. Each is a decision to wait, with the
condition that ends the wait.

## Context

`hegel_note` and `hegel_test_case_printer` both write to the document that
the engine keeps for each test case. `hegel_test_case_printer` fetches a
handle onto the test-case handle's print region. `hegel_note` appends a
string to the same region, one output line for each line of the note, and
the header says that notes and drawn values from one handle appear in the
order they were appended. The document stays readable after
`hegel_mark_complete`, so a client can assemble its output while drawing and
read it back afterwards.

`hegel_run_result_error_kind` reports why a run ended in
`HEGEL_RUN_STATUS_ERROR`: a failed health check, which it names as a
`hegel_health_check_t` value, a flaky or nondeterministic test, an
unsatisfiable one, a misuse of libhegel at run scope, or an internal
invariant. The header says the message from `hegel_run_result_error` is for
people, and that a binding should choose which error to raise from the kind
without parsing the message.

`TestCase#note` records `[:note, message]` in the same entry list that
`TestCase#record_draw` fills with `[:draw, name, value]`, and
`Hegel::Report` renders both from that list when it assembles the failure
report. This gem never opens the engine's printer, so the engine's document
holds nothing.

`Hegel::Runner` reads a run's error through `hegel_run_result_error` alone
and raises `Hegel::Error` with that message. hegel-rust declares
`hegel_run_result_error_kind` in its generated bindings,
`frontends/rust/src/ffi/sys/fns.rs` and `frontends/rust/src/ffi/sys/types.rs`,
and its safe wrapper in `frontends/rust/src/ffi.rs` reads a run's error
through the message, with `hegel_run_result_error`.

## Decision

**`TestCase#note` stays on the Ruby side.** `hegel_note` writes into the
engine's print document, and that document is only worth reading when the
draws are written there too, through `hegel_test_case_printer`. Moving the
notes alone would take them out of the entry list that `Hegel::Report`
renders, so they would vanish from the report. It would also split the
ordering the header promises, because a note in the engine's document and a
draw in the Ruby list have no shared sequence. The two move together, when
this gem adopts the printer for draws.

**`hegel_run_result_error_kind` is not bound.** hegel-rust's frontend takes a
run's error as a message, so a classified `Hegel::Error`, one subclass for a failed
health check and another for an unsatisfiable run, would be a feature that
this gem alone has. ADR 0015 calls that a divergence. The route is a
proposal at hegeldev/hegel: if the shared interface settles on classified
run errors, this gem takes the names and the semantics that were settled
on, and binds the call then.

## Consequences

A note keeps its present cost: one entry in a Ruby array, in the cases that
record.

A caller who needs to tell a failed health check from an unsatisfiable run
reads the message of the `Hegel::Error`, as before. The message wording may
change between engine releases, and the header says so; that is the cost of
waiting for the shared interface.

Revisit the first decision together with the adoption of
`hegel_test_case_printer`, and the second when hegeldev/hegel settles on
classified run errors.
