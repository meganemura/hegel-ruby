---
name: new-generator
description: "How to add a new generator to hegel-ruby. Use when asked to implement, add, or write a generator for a type -- e.g. 'add a generator for UUID', 'implement a generator for Date', 'write a generator for URL'. Covers the generator class, do_draw validation, Hegel::Syntax::Methods wiring, sig/hegel.rbs signatures, and the required test set."
---

# Adding a New Generator

A reference for implementing a single new generator, distilled from the
twenty-five this gem already ships (`lib/hegel/generators.rb`). Read whichever
is closest to your case before starting:

- `IntegerGenerator` -- the shortest form: one primitive, one boundary check.
- `ArrayGenerator` -- the compound form: two nested spans, the
  `new_collection`/`collection_more`/`collection_free` protocol, `ensure` on
  both.
- `TextGenerator` -- a generator that opens a native handle for the
  duration of one draw.

## Implementation pattern

A generator is a `Hegel::Generator` subclass (`lib/hegel/generator.rb`) added
to `lib/hegel/generators.rb`, four pieces:

1. **`initialize` holds options, nothing else.** No validation here --
   `IntegerGenerator#initialize` just assigns `@min_value`/`@max_value`.
   Building an invalid generator must not raise
   (`test_invalid_generator_options_do_not_raise_until_draw_time`).
2. **`do_draw(tc)` validates first, then draws.** Every invalid combination
   of options is caught here with `raise Hegel::Error, "<message>"`, before
   any native call.
3. **Validation messages are prefixed with the bare factory-method name**,
   not the class name: `integers`, not `IntegerGenerator`. Example, verbatim
   from `IntegerGenerator#do_draw`: `"integers: max_value < min_value"`. These
   messages are public API -- tests assert a stable substring
   (`assert_includes error.message, "max_value < min_value"`), so keep the
   wording once it ships.
4. **Compound generators wrap a span, closed by `ensure`.**
   `ArrayGenerator#do_draw` wraps the whole array in
   `HEGEL_LABEL_LIST`/`stop_span` and wraps each element in
   `HEGEL_LABEL_LIST_ELEMENT`/`stop_span`, both inside `ensure`. A missing or
   misplaced span does not fail a test outright; it shrinks to a
   larger-than-minimal counterexample instead (see Test 3 below).

   **Open a span only around a generator that makes more than one native
   call for one drawn value.** A container with elements opens a pair
   (`LIST`/`LIST_ELEMENT`, `SET`/`SET_ELEMENT`, `MAP`/`MAP_ENTRY`);
   `SampledFromGenerator`, `OneOfGenerator`, `OptionalGenerator`, and
   `TupleGenerator` each open one span around the whole draw.

   A generator that makes exactly one native call opens none, even when a
   label with its name sits in the `HEGEL_LABEL_*` table. The header calls
   those "emitted internally, like every per-draw label": the engine opens
   them inside its own draw. `UuidsGenerator` is one such — a label exists,
   and the generator opens no span. Presence in the table is not the test;
   how many native calls the draw makes is.

   One that makes **none** opens none either. `DeferredGenerator` forwards
   to whatever `#set` installed and calls nothing itself; hegel-rust,
   hegel-cpp, and hegel-java all forward the same way, with no span.

**A generator that hands its own block a draw surface must hand it a
non-recording one.** `CompositeGenerator` gives the caller's block a wrapper
rather than the real `Hegel::TestCase`, so the block's inner draws reach the
engine without each claiming its own line in the failure report. The
one-compound-draw-one-report-line rule holds for a generator an author
writes in a block exactly as it does for one written as a class.

**A collection that keeps rejecting is already bounded; do not bound it
again.** `SetGenerator` and `HashGenerator` call
`TestCase#collection_reject` when a drawn element duplicates one they
already hold. Measured against 0.32.5: a single collection tolerates a few
consecutive rejects and then raises `HEGEL_E_ASSUME`, which the run loop
records as a discarded case; a run that keeps discarding trips libhegel's
own FilterTooMuch health check and surfaces as `Hegel::Error`, usually
within a handful of cases and inside a few milliseconds. Neither a retry
loop nor a timeout belongs inside a generator.

**Native handles are freed in `ensure`, never cached on the generator
instance.** See the comment above `TextGenerator#do_draw`: the handle is
scoped to one `TestCase`, and the same generator object can be drawn again
later against a different one, so caching would free the wrong run's handle.

**Only `Hegel::TestCase#draw` (and `#draw_integer`/`#draw_boolean`) record a
value for the failure report.** `TestCase`'s own class comment states this
directly: the non-recording primitives (`generate_integer`,
`generate_boolean`, `generate_string`, ...) exist so a compound generator
making several native calls still produces exactly one report line for the
value it built, not one per call. Call the `generate_*` primitives, or an
inner generator's `do_draw` (as `ArrayGenerator#draw_element` does), from
inside `do_draw`, never `tc.draw`.

## Wiring

- Add the factory method to `Hegel::Syntax::Methods`
  (`lib/hegel/syntax/methods.rb`) -- its own header comment names this "the
  one place any of these five methods is defined."
- Add the class and method signatures to `sig/hegel.rbs`.
- If the generator needs a new native call, add the binding to
  `lib/hegel/lib_hegel/real.rb`, and at the same time: a matching method on
  `test/support/fake_lib_hegel.rb`'s `Fake`, a new entry in
  `Hegel::LibHegel::METHODS` (`lib/hegel/lib_hegel.rb`), and let
  `test_real_and_fake_respond_to_every_libhegel_method`
  (`test/hegel/test_lib_hegel.rb`) confirm both implement it.
- **Bound is not the same as callable.** A call an earlier batch bound can
  still have no `Hegel::TestCase` wrapper, which is what a `do_draw` calls.
  `collection_reject` was bound for a whole milestone before
  `SetGenerator` needed it and found no wrapper there. Check `test_case.rb`
  before assuming.

## Required tests

Modeled on hegel-rust's own `new-generator` skill, translated to this
suite's shape:

1. **Sanity** -- draws against the real engine with no options
   (`test_integers_draws_against_the_real_engine`).
2. **One test per option**, asserting the drawn value respects it
   (`test_integers_min_value_bounds_the_draw`).
3. **Composition inside `arrays(...)`** -- the layer that exercises span
   placement. `test_arrays_composed_with_integers_shrinks_to_the_minimal_duplicate_pair`'s
   own comment: this shrinks to `[0, 0]` only when `HEGEL_LABEL_LIST` and
   `HEGEL_LABEL_LIST_ELEMENT` sit correctly; a missing or misplaced span
   shows up as a larger-than-minimal counterexample, which the `[0, 0]`
   assertions turn into a failure.
4. **One test per validation** -- draw-time raise
   (`test_integers_min_value_greater_than_max_value_raises_at_draw_time`),
   plus one proving construction alone does not raise
   (`test_invalid_generator_options_do_not_raise_until_draw_time`).
5. **Recommended: a randomized-bound property test**, using Hegel itself to
   draw the bounds, apply them, draw a value, and assert it stays in range.
   Model the shape on hegel-rust's
   `tests/test_strings.rs:test_text_codepoint_range`.

Do not add explicit edge-case tests beyond the five above. Two of them go
vacuous or fragile in specific shapes, and a vacuous test is worse than no
test because it reads as coverage:

- **A test that the result holds no duplicates proves nothing when the
  result is a `Set` or a `Hash`'s keys** — the type forbids them however
  the generator behaves. Assert reachability instead: draw from a narrow
  but feasible domain with `min_size == max_size` and assert the result
  reaches that size. Deleting the reject branch then fails the test.
- **Do not assert on a report's rendered text when the drawn value's own
  `#inspect` varies across the supported Rubies.** `Set[0]` on Ruby 4.0 is
  `#<Set: {0}>` on 3.3 and 3.4, and CI runs all three. Assert on a message
  the test itself built.
- **A round trip cannot check a byte convention.** Where a draw needs a
  Ruby-side encode/decode pair — `generate_integer_big` takes and returns
  two's-complement little-endian — `decode(encode(n)) == n` passes just as
  happily if both halves are big-endian. Pin the convention with a
  degenerate draw against the real engine, `min == max` at a value only the
  right byte order reproduces, and keep the round trip for the arithmetic.
- **To see an engine's argument-validation error, drive a real run.** A
  draw call checks its test-case handle before anything else, so a bare
  context with no live test case answers `HEGEL_E_INVALID_HANDLE` whatever
  else is wrong with the call.
- **A struct passed by value needs a degenerate draw against the real
  engine, at a value whose fields all differ.** `FFI::Struct` computes the
  layout, so nothing here can drift from a hand-computed offset; what can
  still be wrong is the field list itself, transcribed from `hegel.h` by
  hand. A `min == max` draw catches that. Give it `13:45:06.123456`, not
  `00:00:00` or `23:59:59` — a boundary value is symmetric under swapping
  minute and second, so a transcription that transposes them would pass.
- **A stdlib type does not resolve in `sig/hegel.rbs`.** The completion
  check is bare `rbs -I sig validate` with no `-r`, so `Date` and `IPAddr`
  fail to resolve while `Time` and `String`, being core, do not. Declare a
  stdlib-typed return as `untyped`.

## Final checklist

- [ ] `initialize` only assigns; `do_draw` validates then draws
- [ ] Validation messages prefixed with the bare factory-method name
- [ ] Compound draws spanned, closed in `ensure`
- [ ] Native handles freed in `ensure`, not cached
- [ ] Wired in `Hegel::Syntax::Methods` and `sig/hegel.rbs`
- [ ] New native call: bound in `real.rb`, `Fake`, `METHODS`, and the
      conformance test, together
- [ ] Tests 1-4 written, test 5 considered
- [ ] `bundle exec rake` passes (100% line and branch coverage)
- [ ] `bundle exec rbs validate` passes
- [ ] `git grep -l FFI:: lib/` still returns exactly `lib/hegel/lib_hegel/real.rb`
