# 0034: Repeat a test body with a Ruby-side indent

## Status

Accepted.

## Context

hegel-rust's `TestCase::repeat` (`frontends/rust/src/test_case.rs:808` in
hegeldev/hegel) runs a closure "logically infinitely": until the engine
ends the loop, or until the closure fails. Under ADR 0015 this gem takes
the same name and the same meaning. Four parts of the Rust version need a
Ruby construction, because Ruby reaches the engine and reports a failure
differently.

What the Rust version does:

1. It draws the loop's minimum length silently, from `integers` up to
   `max_safe_min_size`, which is `2**40` (`test_case.rs:811`). It opens a
   collection with that minimum and no maximum, and loops while the
   collection wants another element.
2. Each iteration notes `// Repetition #N` (`test_case.rs:819`) and runs
   the closure under `enter_block(2)`, a handle from
   `hegel_test_case_block`. The doc comment above the function says
   `// Loop iteration N`; the code and the snapshots in
   `frontends/rust/tests/test_loop.rs` say `// Repetition #N`, and this gem
   follows the code.
3. A closure that panicked with `AssumeFailed` goes on to the next
   iteration. `StopTest`, `InvalidArgument`, and `InternalError` unwind
   unchanged. Any other panic draws one silent boolean and then unwinds.
4. When the collection says no more, it raises `LoopDone`
   (`test_case.rs:842`). The function's return type is `!`: it never
   returns. `run_lifecycle.rs:318` maps `LoopDone` to a VALID test case.

`hegel_test_case_block` (`libhegel/include/hegel.h:1589`) gives a handle
whose print region is a block nested in the parent's, each line indented
further. It indents what reaches the engine printer, and nothing else:
"everything printed or noted through the handle ... lands there". This gem
builds its failure report in Ruby (`Hegel::Report`, with names from
ADR 0005), and neither notes nor draws reach the engine printer. A block
handle would change nothing a caller sees.

## Decision

**`TestCase#repeat` never returns from the loop's end.** It raises
`Hegel::LoopDone`, a control exception beside `Hegel::StopTest` and
`Hegel::AssumeFailed`. It descends from `Exception`, as `CLAUDE.md` requires
of every control exception, so that a `rescue => e` written around the loop
cannot catch the end of it. `Hegel::Runner.classify` maps it to VALID, after
the four fatal exceptions and in the same group as the other control
exceptions.

**One iteration rescues in this order.** First the fatal exceptions
(`Hegel::FATAL_EXCEPTIONS`), `Hegel::StopTest`, `Hegel::LoopDone`, and
`Hegel::Error`: each re-raises unchanged. `Hegel::LoopDone` here is the
end of a nested loop, which ends the outer loop too, as the inner
`LoopDone` unwinds through the outer loop in Rust. `Hegel::Error` stands
where `InvalidArgument` and `InternalError` stand, since this gem raises
both kinds of error as `Hegel::Error`. Next `Hegel::AssumeFailed`, which
skips to the next iteration. Last, any other `Exception`: one boolean is
drawn, without recording, and the exception re-raises. The collection is
freed in an `ensure`, on every path out of the loop.

**The indent lives in the recorded entries.** Each entry
`Hegel::TestCase` records carries an indent, in columns:
`[:draw, name, value, indent]` and `[:note, message, indent]`.
`TestCase#repeat` raises the indent by 2 around each iteration's block,
after the `// Repetition #N` note, and `Hegel::Report` puts that many
spaces before the line. The rendered report reads:

```
  // Repetition #1
    n = 5
```

The indent is the one `enter_block(2)` gives. Nested loops add up, as
blocks do.

**`break` ends the loop.** A Ruby block can `break`, and Rust's closure has
no way to. The `break` returns from `TestCase#repeat` with its value. The
collection is freed and the indent restored on the way out, and the test
body goes on after the loop. Forbidding `break` would turn the ordinary way
out of a Ruby loop into an error. Taking it as the end of the loop gives it
the meaning it has in `loop`, `each`, and `while`.

Two smaller choices follow this gem's own rules:

- The minimum length is drawn with no span around it. hegel-rust's
  `draw_silent` opens a span around every draw. This gem opens one only
  around a generator that makes more than one native call
  (`.claude/skills/new-generator`), and one `hegel_generate_integer` is a
  single call.
- Draw names are suffixed over the whole test case, as
  `Hegel::Report.assign_names` decides: a name gets a counter only when it
  appears more than once in the report. A draw named `x` that appears once
  stays `x`. hegel-rust's snapshots show `x_1` for the same case, because
  its macro marks every draw inside a nested block as repeatable
  (`frontends/rust/macros/src/common.rs:180`), and a repeatable name always
  takes a counter.

## Consequences

A test body can hold a sequence of operations whose length the engine
chooses and shrinks, without a state machine. The tests in
`test/hegel/test_repeat.rb` port the four snapshots and the two run tests of
`test_loop.rs`, and pin the rescue order against the Fake.

The entry format has an indent in every entry. A later feature that wants
an indented section, such as a stateful rule's body under its step line,
can raise the same indent.

`break` is a construction this gem has and hegel-rust lacks. ADR 0015 keeps
mechanism outside its rule, and `break` is the loop exit a Ruby block
already has, so this record treats it as mechanism. If upstream settles a
way to end the loop early, this gem takes that and this record gets a
successor.

If this gem moves its report into the engine printer, `TestCase#repeat`
can open a `hegel_test_case_block` handle for each iteration in place of
the recorded indent.
