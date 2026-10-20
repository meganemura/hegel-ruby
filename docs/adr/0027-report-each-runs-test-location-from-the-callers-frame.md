# 0027: Report each run's test location from the caller's frame

## Status

Accepted.

## Context

`hegel_settings_set_test_location` takes the file, the first line, the
enclosing class, and the name of the test function. Under Antithesis, which
the engine detects through `ANTITHESIS_OUTPUT_DIR`, the engine appends one
`always` assertion named `<class>::<function> passes properties` to
`sdk.jsonl` in that directory, located at `file:begin_line`. Outside
Antithesis it uses nothing. hegel-rust fills the four values in
`#[hegel::test]` from `file!()`, `module_path!()`, the function name, and
`line!()`, and takes no keyword for them.

Ruby has no macro that sees the definition. A `Hegel.test` call can read its
own caller's frame with `caller_locations`, and a frame label in Ruby 3.4
reads `Class#method` or `Class.method`, with `block in ` or
`block (2 levels) in ` in front of it inside a block. A call at the top of a
file, which is where an RSpec example sits, has the label `<main>` or
`<top (required)>`, and a frame whose method is defined on an anonymous
class has the bare method name.

## Decision

`Hegel.test` builds one `Hegel::TestLocation`, a `Data` of `file`,
`begin_line`, `class_name`, and `function`, and hands it to `Runner.run`.
`Runner.run` calls the setter after `Settings.apply` and before it starts
the run or replays a blob. The location is identity, not a setting, so
`Settings.apply` does not take it, and `Hegel.test` has no keyword for it.

The frame is the first one that `Runner.infrastructure?` does not call
infrastructure, the same rule that names the origin of a failure (see
[ADR 0012](0012-build-a-failure-origin-from-the-callers-own-frame.md)). A
wrapper in this gem, a gem, or the standard library is therefore never named
as the test.

`file` is the frame's absolute path made relative to `Dir.pwd` when it lies
under it, and absolute otherwise. `begin_line` is the frame's line, the line
of the `Hegel.test` call.

A label that splits as `Class#method` or `Class.method`, after the `block
... in ` prefix is stripped, gives `class_name` and `function`. Any other
label has no name of its own, so `class_name` is the `file` without `.rb`
and `function` is `line <n>`. Two examples in one spec file then report two
assertions, where one shared name would merge them into one that fails when
either fails.

## Consequences

The line is that of the call, where hegel-rust's is that of the function's
definition, so a method with two `Hegel.test` calls reports two assertions
with the same name at two lines.

A caller cannot choose the name. hegel-rust's macro derives it as well, so a
keyword would be a change to the shared interface, which starts as a proposal
upstream (see
[ADR 0015](0015-follow-the-hegeldev-interface-and-take-changes-upstream-first.md)).

The cost is one `caller_locations` call and one regular expression match for
each `Hegel.test` call, none for each test case.
