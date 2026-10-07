# 0020: Derive span labels from generator names

## Status

Accepted.

## Context

`hegel_start_span` takes a label. Up to libhegel 0.38, `hegel.h` defined a
table of `HEGEL_LABEL_*` constants, and this binding passed the matching
constant for each kind of compound draw: a list, a list element, a map
entry, and so on.

libhegel 0.39.0 removed the table. A label is now an opaque u64 that names
the generator which opened the span. The engine treats two spans with one
label as draws of one generator, and swaps, duplicates, or reorders them
when it shrinks and mutates a test case. The header asks a binding to
derive labels from names of its own, prefixed with the binding's name to
keep clear of the engine's own `hegel.<kind>` names. It asks a generator
built from other generators to combine its own label with its components'
labels, so that `lists(integers())` and `lists(text())` differ.
`hegel_label_from_name` is 64-bit FNV-1a over the name's bytes, and the
header says a binding may compute it ahead of time. hegel-rust computes
both functions in the language and pins its hash against the engine's.

The other implementations differ on names and on combining. hegel-java
hashes `dev.hegel.*` names in Java, hegel-cpp calls
`hegel_label_from_name` with `hegel-cpp.*` names, hegel-go hashes the Go
type, and hegel-typescript passes small integers. Labels are not part of
any implementation's public interface.

## Decision

A generator's label comes from its class name with a `hegel-ruby.`
prefix. A generator built from others combines its own class label with
the labels of the generators it draws from, in order. Both functions are
computed in Ruby, with the same hash the header defines, and a test pins
them against vectors measured from the engine's own functions.

A compound generator computes its label the first time it is drawn, and
keeps it. Computing it at construction was refused, because a generator
validates its arguments when it is drawn, and a component that is not a
generator would then fail at construction with a different error.

A deferred generator answers with its installed generator's label. A
self-referential definition asks for its own label while it computes it,
and the nested ask answers with the deferred class's own label, which ends
the cycle. hegel-rust's deferred generator breaks the cycle the same way.

The span sites stay where they were: around each compound draw, and around
each element of a collection, labelled with the element generator's own
label.

## Consequences

`Hegel::LibHegel` loses the `HEGEL_LABEL_*` constants and gains
`label_from_name` and `label_combine`. A generator class written outside
this library gets a label from its own class name with no extra code.
Renaming a generator class changes its label, which affects nothing past
the run that uses it.
