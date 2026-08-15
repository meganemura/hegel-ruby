# Architecture

## Status

`Hegel.test` runs. It drives a property to a verdict, shrinks a failure to
its minimal counterexample, and re-raises that case's own exception with
its class intact.

What exists: library resolution (`Hegel::Locate`, the pinned
`Hegel::LIBHEGEL_VERSION`, and the development-only `libhegel:fetch` Rake
task), the libhegel binding (`Hegel::LibHegel`, with a real implementation
over Fiddle and a fake for tests), the settings mapping, `Hegel::TestCase`
wrapping the engine's whole draw surface, and the run loop.

What exists beyond that: the failure report, which names drawn values by
reading the caller's own source, interleaves them with whatever `tc.note`
recorded, and prints a blob that `Hegel.test(reproduce_failure:)` replays.
The generator layer covers twenty-five generators composing through `map`
and `filter`, reachable bare through `Hegel::Syntax::Methods`. A test case
can discard itself with `tc.assume` or `tc.reject`. A run can be shaped by
`phases:`, `suppress_health_check:`, `report_multiple_failures:`, and — as
[ADR 0009](adr/0009-turn-the-example-database-on-with-a-key.md) decides —
the example database, through `database_key:` and `database:`.

`tc.target` records an observation for the engine to search toward, and
`Hegel::Stateful.run` drives a `Hegel::StateMachine`'s rules and invariants,
drawing values an earlier rule produced back out of a
`Hegel::Stateful::Pool`. [ADR 0010](adr/0010-declare-stateful-rules-with-a-class-macro.md)
decides how a machine declares its rules and
[ADR 0011](adr/0011-let-the-test-case-own-every-pool-drawn-from-it.md) who
frees a pool.

Every feature this binding set out to cover now has a Ruby surface. What
remains open is not a feature but a measurement, and
[ADR 0008](adr/0008-revisit-the-binding-after-milestone-c-on-measurement.md)
schedules it.

## Where meaning comes from

libhegel is hegel-rust's native engine. hegel-rust's Cargo workspace builds
it from the `hegel-c` directory, as the crate `hegeltest-c`, whose header is
`hegel-c/include/hegel.h`. That header defines the ABI this gem calls: what
each function does, what its error codes mean, and who owns each pointer.

The Java, Go, TypeScript, OCaml, and C++ implementations bind the same
engine. Each works under a constraint hegel-rust does not have: a dynamic
loader, a garbage collector, or a package manager that ships prebuilt
binaries. Where this document cites one of them, it cites a binding
mechanism, not the meaning of a call.

## libhegel and the Ruby boundary

libhegel runs in the same process as its caller. Nearly every function in
`hegel.h` takes a `hegel_context_t*` as its first argument and returns a
`hegel_result_t` status code. `hegel_context_new` returns the context
itself instead. `hegel_context_last_error` returns a borrowed message
pointer instead of a status code.

Ruby calls this ABI through Fiddle. See
[ADR 0001](adr/0001-bind-libhegel-through-fiddle.md).

## FFI confined to one module

Every raw Fiddle call lives in `Hegel::LibHegel`. The rest of the
library calls that module's wrappers, never Fiddle directly. This gives
the library one seam where a test can substitute a fake implementation,
exercising libhegel's error codes without loading the real engine.

## Run loop ownership

The Ruby side owns the run loop. It starts a run, asks libhegel for
each test case, calls the caller's test body, and reports the result back.
A test body's own assertion failure must not cross the C boundary as if it
were a crash.

Ruby's test frameworks complicate this. With minitest 5.27.0, the version
this gem's `Gemfile.lock` pins, `Minitest::Assertion.superclass` is
`Exception`. With rspec-expectations 3.13.5,
`RSpec::Expectations::ExpectationNotMetError.superclass` is `Exception`
as well. By default, `rescue => e` catches only `StandardError`. A run
loop written that way would let a failing assertion pass by uncaught,
instead of being reported as a Hegel failure.

Read the superclass rather than the full ancestor list. `ancestors` also
reports what a given load order mixed into `Object`, so it answers a
different question on a run that loaded `minitest/spec` than on one that
did not.

The run loop `rescue`s `Exception` and re-raises the library's own control
exceptions first. Those control exceptions themselves descend from
`Exception`, not `StandardError`, so a test body's own `rescue => e` cannot
swallow them mid-run. `Hegel::Error`, which reports ordinary library errors
to a caller outside a run, stays a `StandardError`.

## Native handle lifetime

Every `hegel_*_free` function in `hegel.h` takes the handle's owning
context as an argument, so the context must outlive every handle allocated
from it. Ruby's garbage collector does not guarantee finalizer ordering
between a context and its handles.

The code that owns a run releases its handles in an `ensure` block,
freeing every other handle before the context. A finalizer may back up an
`ensure` block that a raised exception skipped, but it must free nothing a
prior `ensure` already freed.

A pool is the one handle a caller's own code opens, inside a rule, where
there is no `ensure` of its own to release it. `Hegel::TestCase` records
every pool opened from it and `Hegel::Runner` releases them alongside the
test-case handle, in nested `ensure`s so a failure releasing one cannot skip
the other. See
[ADR 0011](adr/0011-let-the-test-case-own-every-pool-drawn-from-it.md).

## A rule's own control flow

Inside a stateful rule, `tc.assume(false)` means something narrower than it
does in a test body. `Hegel::Stateful` catches it, tells libhegel the rule
was rejected so the attempt does not spend a step, and draws another rule;
the test case continues. `Hegel::Runner.classify` never sees it, and no case
is discarded.

A rule is also the one place in this library where a process-ending
exception can be raised inside an open span, which is why
`Hegel::FATAL_EXCEPTIONS` lives beside the other control exceptions rather
than beside the run loop: two `rescue Exception` sites need it now, and both
have to let those four straight through before anything else.

## Generator validation happens at draw time

hegel-rust's own contributor documentation states the rule for its
generators: every invalid combination of builder values must be caught at
draw time. The check does not run when the generator is built. The same
documentation treats a validation message as public API, asserted against
by tests as a stable substring. `integers(min_value: 5, max_value: 1)`
therefore returns a generator; the error arrives from `tc.draw`.

## Passing a struct by value

Fiddle has no struct-by-value argument. `Fiddle::Function` converts each
entry of its argument-type list with `NUM2INT`
(`ext/fiddle/function.c`), so an entry must be one of the integer
`Fiddle::TYPE_*` constants; a `Fiddle::CStruct` subclass and an array of
types each raise `TypeError`. Measured on fiddle 1.1.8.

Exactly three ABI functions take a struct by value:
`hegel_generate_date`, `hegel_generate_time`, and
`hegel_generate_datetime`, each receiving two bound values.

They are reached anyway, because passing the struct is not what the call
needs — putting its bits where the ABI puts them is. `hegel_date_t` and
`hegel_time_t` are eight bytes of integers, which arm64, System V, and
Win64 all pass in one general-purpose register: the same register a
`uint64` argument uses. Declaring the parameter `TYPE_UINT64_T` and
passing the packed bits therefore produces the same call. Measured
against libhegel 0.32.5 on arm64-darwin, drawing dates and times inside
their requested bounds.

`hegel_datetime_t` is sixteen bytes, and there the ABIs diverge: arm64 and
System V pass it in two registers, which two `uint64` arguments reproduce,
while Win64 passes anything over eight bytes by reference. The two-register
form is verified on arm64-darwin; CI's windows-latest job is what confirms
or refutes it for Win64, and a failure there is a real finding rather than
a flake.

Anything a packed struct relies on — a field offset, a size — belongs in a
test, so that a layout change upstream fails loudly instead of drawing
plausible nonsense.

## Open questions

- Whether the vendored `linux` binaries run under musl (Alpine) has not
  been checked.
- Whether `Fiddle::Closure` behaves the same across the fiddle versions
  Ruby 3.3 through 4.0 bundle (1.1.2 through 1.1.8) has not been checked.
  Nothing depends on it yet: the engine's output callback is passed as NULL,
  which the ABI documents as leaving output on stderr.
- How Fiddle's `dlopen`-based loading searches for a DLL on Windows has not
  been checked.

## Answered

A drawn string arrives as a pointer and a length, is not NUL-terminated,
and can hold interior NUL bytes, because the drawn alphabet can include
U+0000. Read by length. Measured against 0.32.5: an alphabet pinned to
U+0000 produces a three-byte draw that reads as `""` through
`Fiddle::Pointer#to_s` and as three NUL bytes through `#to_str(len)`. Every
string observed reports `valid_encoding?` after `force_encoding(UTF-8)`.

Prism recovers a draw's assignment target through a method chain, an
instance-variable assignment, and an assignment spanning several lines.
Where several assignments cover the draw's line, the innermost one names
it, so wrapping a body in `assert_raises do ... end` or an RSpec
`expect { ... }` keeps the name. Two assignments side by side on one line
name nothing, and so does a draw whose value is never assigned; both fall
back to a number.
