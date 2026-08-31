# 0014: Name a drawn value only when the draw is the whole assigned value

## Status

Accepted.

## Context

[ADR 0005](0005-name-drawn-values-from-the-callers-source-with-prism.md)
recovers a drawn value's name by parsing the caller's source and reading the
assignment that covers the draw's line. Its Consequences section lists three
cases it had not checked: a heredoc, several draws on one line, and a method
chain.

A first use of the gem outside this repository reached one of them. The
caller wrote a draw inside a larger expression:

```ruby
term_start_date = Date.new(tc.draw(integers(min_value: 1904, max_value: 1904)), 2, 29)
```

Measured against libhegel 0.32.5, the failure report printed:

```
term_start_date = 1904
```

The name says "a date". The value is a year. The reader misread that report
twice before adding a `label:`.

`Hegel::DrawName` already carries the rule this breaks. Its own
documentation states it: a wrong name misdirects a reader of the failure
report more than a missing one does, so an ambiguous line returns nil rather
than choosing between candidates. The module applied that rule to two
assignments written side by side, and applied the opposite rule to a draw
buried in one assignment's value.

A draw pulled out into a plain method is a separate case, and it already
worked. Measured on the same engine, a helper whose body reads
`year = tc.draw(integers(min_value: 1900, max_value: 1910))` reported
`year = 1900`. `Hegel::TestCase::DRAW_CALLER_DEPTH` lands on the line that
called the draw, which is the helper's own line, and the name there is the
one the caller wrote.

## Decision

Recover a name only when the assignment's value is the draw call itself: the
value node is a `Prism::CallNode` whose name is one of the methods that reach
`Hegel::TestCase#record_draw`. Any other value node returns nil, and
`Hegel::TestCase#name_for` falls back to the generic name.

The three method names stay in `Hegel::TestCase`, which defines them, and
`Hegel::DrawName.for` takes them as an argument. A fourth draw method then
has one place to be added.

## Consequences

A draw written inside a larger expression reports the generic name and its
value. The reader loses a name and keeps a value that agrees with it. A
caller who wants the name back passes `label:`, which
[ADR 0005](0005-name-drawn-values-from-the-callers-source-with-prism.md)
already gives precedence over the recovered name.

A method chain answers the question ADR 0005 left open, and answers it the
same way: `xs = tc.draw_integer(0, 10).to_s` reports the generic name,
because `xs` holds a String and the drawn value is an Integer.

A draw written inside another draw's arguments shares the enclosing
assignment's name, because the enclosing assignment's value is a draw call
and one line carries both draws. `label:` separates them.

`Hegel::DrawName` now answers a narrower question than its name suggests on
its own, so its documentation states the question it answers and the reason
for the narrowing.
