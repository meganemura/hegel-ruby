# 0035: Defer concurrent state machines and the engine printer

## Status

Accepted.

## Context

libhegel 0.47.2 offers two facilities that hegel-rust uses and this gem
does not: concurrent state machines, and a printer that builds the failure
report inside the engine. ADR 0015 counts a feature that this gem lacks as
a divergence, so each needs a recorded reason. Paths and line numbers
below are in hegeldev/hegel as of libhegel 0.47.2.

### Concurrent state machines

hegel-rust runs a `ConcurrentStateMachine` with `run_concurrent`
(`frontends/rust/src/stateful.rs:989`). `hegel_new_state_machine` draws a
concurrency level between `min_concurrency` and `max_concurrency`.
`run_concurrent_machine` (`stateful.rs:1361`) spawns one thread per level
inside `std::thread::scope` (`stateful.rs:1415`). Each round, it hands every
worker a clone of the test case, `tc.clone()`, attributed to that worker
with `set_worker` (`stateful.rs:1449-1450`). A `ConcurrentRule`'s `apply`
takes `&M` (`stateful.rs:1097-1102`): the doc comment above it
(`stateful.rs:1086-1096`) says the
machine is "shared by reference across the worker threads, so any mutable
model state needs interior mutability", and that the feature "is intended
for advanced users. We otherwise discourage using it."

The engine calls behind this are `hegel_test_case_clone`
(`libhegel/include/hegel.h:1553`), which gives "an independent stream of the
same test case" that "can be driven concurrently from different threads",
and `hegel_test_case_set_worker` (`hegel.h:1614`), which prefixes each line
the handle records with `[worker N +X.XXXms] `.

Four things stand between this gem and a port:

1. **Each worker needs its own context.** The threading section of
   `hegel.h` (lines 101-117) says "A context must not be used concurrently
   from multiple threads". hegel-rust keeps one context per thread in a
   `thread_local!` (`frontends/rust/src/ffi.rs:72`). `Hegel::Runner.run`
   opens one context for the whole run and threads it through every call,
   so each worker would need a context of its own, and every handle
   allocated from it freed before that context.
2. **Ruby threads take turns.** `Hegel::LibHegel::Real#bind` builds each
   `FFI::Function` without the `blocking:` option, so every engine call
   holds the GVL for its duration. Between engine calls, Ruby threads
   running pure-Ruby code switch on the VM's timer or at blocking I/O. A
   short rule body that does no I/O then tends to run to completion before
   another thread gets the GVL, and the interleavings a concurrent machine
   exists to find seldom happen. A body that waits on I/O, a database, or a
   C extension that releases the GVL would interleave.
3. **Ractors cannot reach a shared machine.** Measured with ffi 1.17.4 on
   Ruby 3.4.6: passing an unfrozen `FFI::Pointer` to `Ractor.new` raises
   "cannot duplicate unbounded memory area", and passing an unfrozen
   `FFI::Function` raises "cannot duplicate function instances". Both can
   be made shareable with `Ractor.make_shareable`, and a shareable
   `FFI::Function` is callable inside another Ractor. The handles are not
   the obstacle. The machine is: hegel-rust's rules share one `&M`, and a
   `Hegel::StateMachine` subclass instance with mutable state is an object
   that only one Ractor can reach.
4. **`CLAUDE.md` would change.** Its standing constraints say "The engine
   is single-threaded. A context, a run, and a test case each belong to one
   thread at a time." A concurrent runner needs that rule restated for
   clones and per-thread contexts.

`Hegel::LibHegel::Real#new_state_machine` passes a concurrency of exactly
1, and ADR 0021 records the sequential machine this gem runs.

### The engine printer

hegel-rust prints each drawn value and note into the engine's document as
the test body runs. `hegel_test_case_printer` (`hegel.h:3052`) gives a
handle onto a test-case handle's print region, the `hegel_printer_*`
calls (the comment above `hegel_printer_t`, `hegel.h:538-574`, describes
the model) lay text out in groups that
break to fit a width (default 79, `hegel.h:3073`), `hegel_printer_reflow`
(`hegel.h:2910`) re-lays a flat debug string such as Ruby's `#inspect`, and
`hegel_note` (`hegel.h:3079`) appends a line. A note written while a drawn
value is mid-print is held back and placed after the value (`hegel.h`, the
comment above `hegel_note`). `hegel_test_case_block` (`hegel.h:1589`)
indents a section, and `hegel_test_case_set_worker` prefixes a worker's
lines.

This gem builds its report in Ruby. `Hegel::TestCase` records draws and
notes on the cases the engine stamps for capture (ADR 0019),
`Hegel::DrawName` names each draw from the caller's source (ADR 0005 and
ADR 0014), and `Hegel::Report` renders the list. `Hegel::LibHegel::Real`
passes a NULL output callback to `hegel_run_start`.

## Decision

**Concurrent state machines are not ported.** `Hegel::Stateful.run` stays
sequential, at a concurrency of 1. This is a divergence under ADR 0015,
recorded here. It is to be revisited when a caller asks for it, together
with the engine printer: `hegel_test_case_set_worker` attributes
`hegel_note` lines and lines started through a printer from
`hegel_test_case_printer` (`hegel.h:1595-1599`), so a report that reads
across workers comes from the engine document.

**The engine printer is not adopted for draws.** `Hegel::Report` keeps
building the report. Moving it into the engine would change two things
that work today:

- `Hegel::Report.assign_names` gives a name a counter only when that name
  appears more than once among the whole case's draws (ADR 0014 decides
  which draws get a name at all). At draw time, the rest of the case has
  not run, so the printed name is not yet known.
  `hegel_printer_deferred` could hold each name open until the case ends,
  at the price of one hole per draw and a resolve step this gem does not
  have.
- The report's shape, which `test/hegel/test_report.rb` pins line by line,
  and which a caller reads on every failure.

The gains, width wrapping, a note placed after a value whose generation
emitted it, indented step blocks, and worker prefixes, do not yet outweigh
that.

A narrower change stays open: `Hegel::Report` could lay out a long value
through a standalone document, `hegel_printer_new` (`hegel.h:2746`), and
`hegel_printer_reflow` over the value's `#inspect`, then read it back with
`hegel_printer_value` (`hegel.h:3011`). That brings width wrapping without
moving naming or the report into the engine.

## Consequences

A caller who wants to exercise concurrency can start Ruby threads inside a
single rule. The engine then neither chooses nor shrinks the interleaving.

A long drawn value prints on one line, as `#inspect` writes it.

A later feature that wants an indented section of the report, the effect
`hegel_test_case_block` gives in the engine document, builds that indent in
`Hegel::Report`.

A later record that ports either facility supersedes this one.
