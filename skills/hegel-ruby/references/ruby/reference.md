# Hegel Ruby Reference

## Table of Contents

- [Setup](#setup)
- [Test Structure](#test-structure): `Hegel.test`, its block, return value, failure behavior
- [Settings](#settings): `test_cases:` `seed:` `derandomize:` `verbosity:` `database:` `database_key:` `phases:` `suppress_health_check:` `report_multiple_failures:` `stateful_step_count:` `output:` `reproduce_failure:`
- [TestCase Methods](#testcase-methods): `draw`, `draw_integer`, `draw_boolean`, `assume`, `reject`, `note`, `target`
- [Generator Reference](#generator-reference): `booleans`, `integers`, `floats`, `text`, `arrays`, `just`, `sampled_from`, `one_of`, `optional`, `tuples`, `sets`, `hashes`, `characters`, `binary`, `from_regex`, `emails`, `urls`, `domains`, `ip_addresses`, `uuids`, `dates`, `times`, `datetimes`, `composite`, `deferred`
- [Stateful Testing](#stateful-testing): `Hegel::StateMachine`, `rule`, `invariant`, `Hegel::Stateful.run`, `Hegel::Stateful::Pool`
- [Combinator Methods](#combinator-methods): `.map`, `.filter`
- [Gotchas](#gotchas)

## Setup

Hegel for Ruby is packaged as the `hegeltest` gem. Each platform gem carries
the matching `libhegel` engine, so an install compiles nothing and needs no
engine on the side:

```ruby
# Gemfile
gem "hegeltest"
```

A platform with no published `libhegel` build, such as macOS on Intel, needs
`HEGEL_LIBHEGEL_PATH` pointing at a local build instead.

Require it, then include the generator methods wherever tests draw values:

```ruby
require "hegel"

include Hegel::Syntax::Methods
```

`Hegel::Syntax::Methods` makes every generator method (`booleans` through
`deferred`; see [Generator Reference](#generator-reference)) callable bare,
the way FactoryBot's own `Syntax::Methods` makes `create` callable bare.
With Minitest, include it once on the base test class:

```ruby
require "hegel"

class Minitest::Test
  include Hegel::Syntax::Methods
end
```

Hegel drives `libhegel`, a native engine that ships separately from the gem.
Building or testing this repository from source needs it on hand:

```bash
bundle exec rake libhegel:fetch
```

That downloads the pinned build for the host platform into
`tmp/libhegel/<version>/` and verifies it against its published SHA-256.
`HEGEL_LIBHEGEL_PATH` overrides the bundled engine with a local build.

## Test Structure

`Hegel.test` takes a block, runs it as a property, and returns `nil` on a
passing run:

```ruby
result = Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  n = tc.draw(integers)
  raise "not an integer" unless n.is_a?(Integer)
end
result # => nil
```

The block receives a `Hegel::TestCase` (`tc` above). Draw values from it,
run the code under test, and signal a failure by raising. Any uncaught
exception inside the block is treated as a failing test case. Use whatever
assertion mechanism the surrounding test framework already provides
(RSpec's `expect`, Minitest's `assert_equal`, or a plain `raise`).

On a failing run, `Hegel.test` writes a failure report to `output:`
(`$stderr` by default) and re-raises the smallest failing case's own
exception, class and backtrace intact, so a host test framework reports it
as its own failure rather than a Hegel-specific one. `seed:` and
`derandomize: true` (see [Settings](#settings)) are added below only to
make this example's output reproducible on every run:

```ruby
require "stringio"

def my_sort(ls) = ls.sort.uniq # oops: uniq drops duplicates

output = StringIO.new
begin
  Hegel.test(output: output, seed: 1, derandomize: true) do |tc|
    xs = tc.draw(arrays(integers))
    raise "not sorted-equal" unless my_sort(xs) == xs.sort
  end
rescue => e
  e.class   # => RuntimeError
  e.message # => "not sorted-equal"
end
output.string
```

`output.string` holds:

```
Falsified after 3 test cases (0 discarded):

  xs = [0, 0]

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ=="
```

Hegel names each drawn value (`xs` above) by reading the line the `draw`
call was written on. Pass the blob back through `reproduce_failure:` to
replay that exact failing case without a full run:

```ruby
Hegel.test(reproduce_failure: "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ==", verbosity: :quiet) do |tc|
  xs = tc.draw(arrays(integers))
  raise "not sorted-equal: #{xs.inspect}" unless my_sort(xs) == xs.sort
end
```

## Settings

`Hegel.test` takes these keywords, all optional:

| Keyword | Type | Default | Purpose |
|---|---|---|---|
| `test_cases` | `Integer` or `nil` | `nil` (libhegel's own default: 100) | Number of test cases to run |
| `seed` | `Integer` or `nil` | `nil` (libhegel picks its own) | Fixed RNG seed; pair with `derandomize: true` for a reproducible sequence |
| `derandomize` | `true`/`false` or `nil` | `nil` (libhegel's own default) | Derive the seed deterministically from the test itself, instead of drawing a random one |
| `verbosity` | `Symbol` or `nil` | `nil` (libhegel's own default) | `:quiet`, `:normal`, `:verbose`, or `:debug` |
| `database` | `String` or `nil` | `nil` | The example database's directory; means something only alongside `database_key:` |
| `database_key` | `String` or `nil` | `nil` | Turns the example database on, scoped to this key |
| `phases` | `Array` of `Symbol` or `nil` | `nil` (libhegel's own default: every phase) | Which run phases to enable: `:explicit`, `:reuse`, `:generate`, `:target`, `:shrink` |
| `suppress_health_check` | `Array` of `Symbol` or `nil` | `nil` (no suppression) | Which health checks to turn off: `:filter_too_much`, `:too_slow`, `:test_cases_too_large`, `:large_initial_test_case` |
| `report_multiple_failures` | `true`/`false` | `false` | `true` summarizes every distinct failure into one `Hegel::Error` instead of re-raising a single failure's own exception |
| `stateful_step_count` | `Integer` or `nil` | `nil` (libhegel's own default: 50) | Steps per test case a `Hegel::Stateful.run` call applies, for a stateful test |
| `output` | `IO` | `$stderr` | Where a failure report is written |
| `reproduce_failure` | `String` or `nil` | `nil` | Replays the single case the blob encodes, instead of running a full property |

`nil` means the same thing for `test_cases`, `seed`, `derandomize`,
`verbosity`, `phases`, `suppress_health_check`, and `stateful_step_count`: do
not call the matching libhegel setter, and let the engine's own default
apply. `database`/`database_key` and `report_multiple_failures` each follow
their own rule instead, covered below.

`database_key:` is the switch that turns libhegel's example database on;
`database:` only chooses where it writes, and means nothing without a key.
Passing `database:` alone raises `Hegel::Error` at run time:

```ruby
Hegel.test(database: "/tmp/wherever") { |tc| tc.draw(integers) }
# raises Hegel::Error, "hegel: database: needs database_key: to scope what
# it stores and replays; pass database_key: too, or drop database: and pass
# neither."
```

Give `database_key:` a value unique to the property under test. Two
`Hegel.test` calls that share a key share one replay scope, so an unrelated
property can read or overwrite what this one stored. Left at their shared
default (`nil`, `nil`), a run stores nothing.

`phases:` and `suppress_health_check:` each take an `Array` of `Symbol`, and
each raises `Hegel::Error` at run time for an empty one. An empty `Array`
has no established meaning against libhegel, unlike dropping the keyword
entirely:

```ruby
Hegel.test(phases: []) { |tc| tc.draw(integers) }
# raises Hegel::Error, "hegel: phases expects one or more of [:explicit,
# :reuse, :generate, :target, :shrink], got an empty Array"
```

`report_multiple_failures:` defaults to `false`, which is not libhegel's own
default (`true`). With the default `false`, a run stops at its first failing
example and re-raises that failure's own exception, class and backtrace
intact, so a host framework reports it as its own. `report_multiple_failures:
true` keeps generating afterwards to surface other distinct bugs, and then
raises `Hegel::Error` naming the count instead of any one of the individual
exceptions:

```ruby
Hegel.test(test_cases: 10, report_multiple_failures: true, verbosity: :quiet) do |tc|
  n = tc.draw_integer(0, 1, label: "n")
  if n.zero?
    raise "boom-zero"
  else
    raise "boom-one"
  end
end
# raises Hegel::Error, "Property-based test failed with 2 distinct failures."
```

`stateful_step_count:` bounds how many rules one `Hegel::Stateful.run` call
applies per test case (see [Stateful Testing](#stateful-testing)); the
engine documents its own default as 50, and requires the value be at least
1.

`seed:` and `derandomize: true` together make a run reproducible:

```ruby
seen_a = []
Hegel.test(test_cases: 5, seed: 42, derandomize: true, verbosity: :quiet) do |tc|
  seen_a << tc.draw(integers(min_value: 0, max_value: 100))
end

seen_b = []
Hegel.test(test_cases: 5, seed: 42, derandomize: true, verbosity: :quiet) do |tc|
  seen_b << tc.draw(integers(min_value: 0, max_value: 100))
end

seen_a == seen_b # => true
```

An unrecognized `verbosity:` raises `Hegel::Error` at run time:

```ruby
Hegel.test(verbosity: :chatty) { |tc| tc.draw(integers) }
# raises Hegel::Error, "hegel: unknown verbosity :chatty; expected one of
# [:quiet, :normal, :verbose, :debug]"
```

`verbosity: :quiet` also silences the failure report itself, not just
libhegel's own progress output. Even when `output:` is given, nothing is
written to it.

## TestCase Methods

| Method | Signature | Purpose |
|---|---|---|
| `draw` | `draw(generator, label: nil)` | Draw a value from a `Hegel::Generator`; shown in the failure report under `label`, or a name recovered from the caller's own source line |
| `draw_integer` | `draw_integer(min_value, max_value, label: nil)` | Draw an integer directly, without building an `integers` generator |
| `draw_boolean` | `draw_boolean(p = 0.5, label: nil)` | Draw a boolean directly, without building a `booleans` generator |
| `assume` | `assume(condition)` | Discard this test case (see `reject`) unless `condition` holds, read as Ruby truthiness |
| `reject` | `reject` | Discard this test case unconditionally |
| `note` | `note(message = nil, &block)` | Record `message` (or the block's return value) for the failure report, interleaved with draws in call order |
| `target` | `target(value, label: "")` | Feed `value` to libhegel's own hill-climbing search between generation rounds |

```ruby
result = Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  a = tc.draw(integers, label: "numerator")
  b = tc.draw_integer(1, 1_000)
  c = tc.draw_boolean(0.5, label: "flag")
  raise "bad draw" unless a.is_a?(Integer) && b.is_a?(Integer) && [true, false].include?(c)
end
result # => nil
```

`label:` wins over the name Hegel recovers from the source line, and shows
up in the failure report:

```ruby
output = StringIO.new
begin
  Hegel.test(output: output, seed: 1, derandomize: true) do |tc|
    n = tc.draw(integers(min_value: 0, max_value: 10), label: "count")
    raise "boom" if n > 5
  end
rescue => e
  e.message # => "boom"
end
output.string
```

```
Falsified after 2 test cases (0 discarded):

  count = 6

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AAEAAAAACgEAAAAG"
```

`assume` discards a test case (the same way `reject` does) unless its
condition holds, read as ordinary Ruby truthiness rather than restricted to
`true`/`false`, so `tc.assume(hash[:key])` works directly:

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  n = tc.draw_integer(0, 10)
  tc.assume(n.even?)
  raise "not even" unless n.even?
end
result # => nil
```

`.filter` (see [Combinator Methods](#combinator-methods)) discards a test
case the same way, scoped to one generator's own draw rather than the whole
body; `assume`/`reject` discard from anywhere in the block.

`note` records a message for the eventual failure report, interleaved with
draws in the order both were called. Pass a message directly, or a block.
The block form is evaluated only on the one, already-shrunk replay that
produces the report, so it is the cheaper choice when building the message
itself costs something. Passing both, or neither, raises `Hegel::Error`:

```ruby
output = StringIO.new
begin
  Hegel.test(output: output, seed: 1, derandomize: true) do |tc|
    tc.note("starting the queue")
    n = tc.draw_integer(0, 1_000_000, label: "n")
    tc.note("queue was empty") if n > 500
    raise "too big: #{n}" if n > 500
  end
rescue => e
  e.message # => "too big: 501"
end
output.string
```

```
Falsified after 2 test cases (0 discarded):

  starting the queue
  n = 501
  queue was empty

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AAEAAAAACgIAAAD1AQ=="
```

`target` feeds `value` to libhegel's own hill-climbing search between
generation rounds, under `label` (default `""`); it does not appear in the
failure report. The same `label` used twice on one test case raises
`Hegel::Error`, and so does a non-finite `value` (`Float::NAN` or
`Float::INFINITY`):

```ruby
Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  n = tc.draw_integer(0, 1000)
  m = tc.draw_integer(0, 1000)
  tc.target(n + m, label: "score")
end
```

```ruby
Hegel.test(test_cases: 5, verbosity: :quiet) { |tc| tc.target(1, label: "score"); tc.target(2, label: "score") }
# raises Hegel::Error, "HEGEL_E_INVALID_ARG (-5): tc.target(2, label=\"score\")
# would overwrite previous tc.target(_, label=\"score\"); each label can be
# observed at most once per test case"
```

## Generator Reference

Every generator method lives in `Hegel::Syntax::Methods` (bare, once
included) and as `Hegel::Generators.<name>` (with a module prefix, no
include needed). Both forms build the same generator. Options are keyword
arguments; a generator validates them when it is drawn from, not when it is
built (see [Gotchas](#gotchas)).

### `booleans(p: 0.5)`

A boolean, true with probability `p`.

```ruby
Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  b = tc.draw(booleans)
  raise "not boolean" unless [true, false].include?(b)
end

Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  raise "not true" unless tc.draw(booleans(p: 1.0)) == true # p: 1.0 always draws true
end
```

`p` outside `0.0..1.0` raises `Hegel::Error` at draw time:
`"booleans: p must be between 0.0 and 1.0, got 1.5"`.

### `integers(min_value: nil, max_value: nil)`

An integer in `[min_value, max_value]`. Omitting `min_value` or `max_value`
defaults it to the signed 64-bit boundary (`-2**63` or `2**63 - 1`); an
explicit bound outside that range draws at arbitrary precision instead.

```ruby
Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  n = tc.draw(integers(min_value: 0, max_value: 100))
  raise "out of range" unless n.between?(0, 100)
end

seen = []
Hegel.test(test_cases: 5, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(integers(min_value: 10**20, max_value: 10**20 + 100))
end
seen # => [100000000000000000000, 100000000000000000099, 100000000000000000039, 100000000000000000026, 100000000000000000059]
```

`max_value < min_value` raises `Hegel::Error` at draw time:
`"integers: max_value < min_value"`. Because an omitted bound still
defaults to the 64-bit boundary rather than to an unbounded range, this
also fires for a one-sided big bound: `integers(min_value: 10**30)` raises
the same error, since `max_value` defaults to `2**63 - 1`, smaller than
`10**30` (see [Gotchas](#gotchas)). Pass both bounds explicitly to draw
outside the 64-bit range:

```ruby
Hegel.test(verbosity: :quiet) { |tc| tc.draw(integers(min_value: 10**30, max_value: 10**30 + 100)) }
# => nil
```

### `floats(min_value: nil, max_value: nil, allow_nan: false, allow_infinity: false, exclude_min: false, exclude_max: false)`

A double in `[min_value, max_value]`, unbounded (the full finite range) by
default. Unlike hegel-rust's and hegel-typescript's `floats()`, `allow_nan`
and `allow_infinity` both default to **`false`** here even when fully
unbounded (see [Gotchas](#gotchas)).

```ruby
Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  f = tc.draw(floats(min_value: 0.0, max_value: 1.0, exclude_min: true, exclude_max: true))
  raise "out of open interval" unless f > 0.0 && f < 1.0
end

Hegel.test(test_cases: 200, verbosity: :quiet) do |tc|
  tc.draw(floats(allow_nan: true)) # can now draw NaN
end
```

`max_value < min_value` raises `Hegel::Error` at draw time:
`"floats: max_value < min_value"`.

### `text(min_size: 0, max_size: nil, codec: nil, min_codepoint: nil, max_codepoint: nil)`

A Unicode string of `[min_size, max_size]` characters, unbounded above by
default.

```ruby
Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  s = tc.draw(text(min_size: 1, max_size: 10))
  raise "out of size" unless s.length.between?(1, 10)
end

Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  s = tc.draw(text(codec: "ascii"))
  raise "not ascii" unless s.ascii_only?
end

Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  s = tc.draw(text(min_codepoint: 0x41, max_codepoint: 0x5A))
  raise "out of codepoint range" if s.codepoints.any? { |cp| !cp.between?(0x41, 0x5A) }
end
```

`max_size < min_size` raises `Hegel::Error` at draw time: `"text: max_size <
min_size"`. `alphabet:`, `categories:`, `include_characters:`, and
`exclude_characters:` (character-filtering options other Hegel bindings
expose) are not available in this binding; `codec:`, `min_codepoint:`, and
`max_codepoint:` are the alphabet controls it exposes today.

### `arrays(elements, min_size: 0, max_size: nil)`

An `Array` of values from the `elements` generator, with `[min_size,
max_size]` entries, unbounded above by default.

```ruby
Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  xs = tc.draw(arrays(integers(min_value: 0, max_value: 10), min_size: 1, max_size: 5))
  raise "out of range" unless xs.length.between?(1, 5) && xs.all? { |x| x.between?(0, 10) }
end
```

`max_size < min_size` raises `Hegel::Error` at draw time: `"arrays:
max_size < min_size"`. A negative `min_size` also raises at draw time:
`"arrays: min_size must not be negative"`. `unique:` (deduplicating
elements) is not available on `arrays`; `sets` (below) draws distinct
elements instead.

### `just(value)`

Always `value`, drawing nothing.

```ruby
result = Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  v = tc.draw(just(42))
  raise "not 42" unless v == 42
end
result # => nil
```

### `sampled_from(collection)`

One element of `collection`, picked at random.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(sampled_from([1, 2, 3]))
  raise "not in collection" unless [1, 2, 3].include?(v)
end
result # => nil
```

An empty `collection` raises `Hegel::Error` at draw time:
`"sampled_from: collection must not be empty"`.

### `one_of(*generators)`

A value drawn from one of `generators`, picked at random.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(one_of(just(1), just(2)))
  raise "not in set" unless [1, 2].include?(v)
end
result # => nil
```

Calling it with no `generators` raises `Hegel::Error` at draw time:
`"one_of: at least one generator is required"`.

### `optional(generator)`

A value drawn from `generator` half the time, `nil` the other half.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(optional(just(1)))
  raise "wrong value" unless v.nil? || v == 1
end
result # => nil

seen = []
Hegel.test(test_cases: 10, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(optional(integers(min_value: 0, max_value: 9)))
end
seen # => [nil, 2, 3, 6, 1, 7, 5, 4, 8, 9]
```

### `tuples(*generators)`

An `Array` holding one value drawn from each of `generators`, in order
(Ruby has no tuple type).

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(tuples(integers, text))
  raise "wrong shape" unless v.is_a?(Array) && v.size == 2
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(tuples(integers(min_value: 0, max_value: 9), booleans))
end
seen # => [[0, false], [5, false], [3, false]]
```

Calling it with no `generators` is a valid, zero-length tuple, not an
error:

```ruby
value = nil
Hegel.test(test_cases: 1, verbosity: :quiet) { |tc| value = tc.draw(tuples) }
value # => []
```

### `sets(elements, min_size: 0, max_size: nil)`

A `Set` of values from `elements`, with `[min_size, max_size]` entries,
unbounded above by default.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(sets(integers(min_value: 0, max_value: 100), min_size: 1, max_size: 5))
  raise "wrong type" unless v.is_a?(Set) && v.size.between?(1, 5)
end
result # => nil

seen = nil
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen = tc.draw(sets(integers(min_value: 0, max_value: 9), min_size: 3, max_size: 3))
end
seen.to_a # => [5, 2, 6]
```

`max_size < min_size` raises `Hegel::Error` at draw time: `"sets: max_size <
min_size"`. A negative `min_size` also raises at draw time: `"sets:
min_size must not be negative"`.

### `hashes(keys, values, min_size: 0, max_size: nil)`

A `Hash` whose keys are drawn from `keys` and values from `values`, with
`[min_size, max_size]` entries, unbounded above by default.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(hashes(integers(min_value: 0, max_value: 100), text, min_size: 1, max_size: 5))
  raise "wrong type" unless v.is_a?(Hash) && v.size.between?(1, 5)
end
result # => nil

seen = nil
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen = tc.draw(hashes(integers(min_value: 0, max_value: 9), booleans, min_size: 2, max_size: 2))
end
seen.to_a # => [[5, false], [3, false]]
```

`max_size < min_size` raises `Hegel::Error` at draw time: `"hashes:
max_size < min_size"`. A negative `min_size` also raises at draw time:
`"hashes: min_size must not be negative"`.

### `characters(codec: nil, min_codepoint: nil, max_codepoint: nil)`

A `String` of exactly one character, sharing `text`'s own alphabet options.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(characters(codec: "ascii"))
  raise "wrong shape" unless v.is_a?(String) && v.length == 1 && v.ascii_only?
end
result # => nil

seen = []
Hegel.test(test_cases: 5, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(characters(min_codepoint: 0x41, max_codepoint: 0x5A))
end
seen # => ["A", "Z", "E", "T", "G"]
```

### `binary(min_size: 0, max_size: nil)`

A byte `String` of `[min_size, max_size]` bytes, unbounded above by
default.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(binary(min_size: 1, max_size: 8))
  raise "wrong encoding" unless v.encoding == Encoding::BINARY && v.bytesize.between?(1, 8)
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(binary(min_size: 2, max_size: 2))
end
seen # => ["\x00\x00", "\xCA\x95", "\xD5N"]
```

`max_size < min_size` raises `Hegel::Error` at draw time: `"binary:
max_size < min_size"`.

### `from_regex(pattern, fullmatch: false)`

A `String` matching `pattern` (Python `re` syntax, not Ruby's `Regexp`
syntax). `fullmatch` requires the whole string to match, not just contain
a match.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(from_regex("[a-z]{3}"))
  raise "no match" unless v.match?(/[a-z]{3}/)
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(from_regex("[a-z]{3}", fullmatch: true))
end
seen # => ["aaa", "pgq", "iqy"]
```

`pattern` must be a `String`, not a Ruby `Regexp` (the two grammars diverge
on flags and anchors, so a `Regexp` is rejected rather than silently
translated): `from_regex(/[a-z]{3}/)` raises `Hegel::Error` at draw time,
`"from_regex: pattern must be a String in Python re syntax, not a
Regexp"`. Pass `my_regexp.source` explicitly for a pattern confirmed to
need no flags and to use only syntax the two grammars share.

### `emails`

An RFC 5321/5322 email address `String`.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(emails)
  raise "not a string" unless v.is_a?(String)
end
result # => nil

seen = []
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(emails)
end
seen # => ["0@a.COM"]
```

### `urls`

An RFC 3986 http/https URL `String`.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(urls)
  raise "not a string" unless v.is_a?(String)
end
result # => nil

seen = []
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(urls)
end
seen # => ["http://a.COM/"]
```

### `domains(max_length: 255)`

A fully-qualified domain name `String` of at most `max_length` characters.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(domains(max_length: 20))
  raise "too long" unless v.length <= 20
end
result # => nil

seen = []
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(domains)
end
seen # => ["a.COM"]
```

`max_length` outside libhegel's valid range raises `Hegel::Error` at draw
time, wrapping the engine's own message:

```ruby
Hegel.test(verbosity: :quiet) { |tc| tc.draw(domains(max_length: 3)) }
# raises Hegel::Error, "HEGEL_E_INVALID_ARG (-5): domain max_length=3
# leaves no eligible TLDs"
```

### `ip_addresses(v4: true, v6: true)`

An `IPAddr`, v4 or v6 depending on `v4`/`v6`. With both true (the default),
the family is picked at random for each value.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(ip_addresses)
  raise "not an ipaddr" unless v.is_a?(IPAddr)
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(ip_addresses(v6: false)).to_s
end
seen # => ["0.0.0.0", "172.17.134.161", "15.160.245.253"]
```

`v4: false, v6: false` together raise `Hegel::Error` at draw time:
`"ip_addresses: v4 and v6 must not both be false"`.

### `uuids(version: nil)`

A UUID `String` in the standard 8-4-4-4-12 hex form. `version: nil` (the
default) draws uniform random bits except the nil UUID; an explicit
version forces the RFC 4122 version and variant nibbles.

```ruby
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(uuids)
  raise "wrong shape" unless v.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
end
result # => nil

seen = []
Hegel.test(test_cases: 1, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(uuids(version: 4))
end
seen # => ["00000000-0000-4000-8000-000000000000"]
```

A `version` outside `0..15` raises `Hegel::Error` at draw time, wrapping
the engine's own message:

```ruby
Hegel.test(verbosity: :quiet) { |tc| tc.draw(uuids(version: 16)) }
# raises Hegel::Error, "HEGEL_E_INVALID_ARG (-5): uuid version must be a
# single hex nibble (0..=15), got 16"
```

### `dates(min_value: nil, max_value: nil)`

A proleptic Gregorian calendar `Date` in `[min_value, max_value]`,
defaulting to year 1 through year 9999.

```ruby
Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(dates(min_value: Date.new(2020, 1, 1), max_value: Date.new(2020, 12, 31)))
  raise "out of range" unless v.between?(Date.new(2020, 1, 1), Date.new(2020, 12, 31))
end

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(dates(min_value: Date.new(2020, 1, 1), max_value: Date.new(2020, 12, 31))).to_s
end
seen # => ["2020-01-01", "2020-07-23", "2020-04-28"]
```

`max_value < min_value` raises `Hegel::Error` at draw time: `"dates:
max_value < min_value"`.

### `times(min_value: nil, max_value: nil)`

A time of day `String`, `"HH:MM:SS.ffffff"`, in `[min_value, max_value]`
(also `"HH:MM:SS.ffffff"` Strings), defaulting to the full day.

```ruby
Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(times(min_value: "09:00:00.000000", max_value: "17:00:00.000000"))
  raise "out of range" unless v.between?("09:00:00.000000", "17:00:00.000000")
end

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(times(min_value: "09:00:00.000000", max_value: "17:00:00.000000"))
end
seen # => ["09:00:00.000000", "09:00:33.554432", "09:00:00.002652"]
```

`max_value < min_value` raises `Hegel::Error` at draw time: `"times:
max_value < min_value"`. A bound that is not a `"HH:MM:SS.ffffff"` String
also raises at draw time: `times(min_value: "1:2:3.4")` gives `'times:
min_value must be "HH:MM:SS.ffffff", got "1:2:3.4"'`.

### `datetimes(min_value: nil, max_value: nil)`

A naive (no timezone) `Time` in `[min_value, max_value]`, defaulting to
year 1 through year 9999.

```ruby
Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(datetimes(min_value: Time.utc(2020, 1, 1), max_value: Time.utc(2020, 12, 31, 23, 59, 59)))
  raise "not a Time" unless v.is_a?(Time)
end

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(datetimes(min_value: Time.utc(2020, 1, 1), max_value: Time.utc(2020, 12, 31, 23, 59, 59))).to_s
end
seen # => ["2020-01-01 00:00:00 UTC", "2020-07-23 00:00:00 UTC", "2020-04-28 00:00:00 UTC"]
```

`max_value < min_value` raises `Hegel::Error` at draw time: `"datetimes:
max_value < min_value"`.

### `composite(&block)`

A value built from imperative code: `block` receives a draw surface and
may call `#draw` (or the direct `#draw_integer`/`#draw_boolean`
primitives) on it any number of times to assemble one value.

```ruby
pair = composite { |dtc| [dtc.draw(integers(min_value: 0, max_value: 10)), dtc.draw(text(max_size: 5, codec: "ascii"))] }
result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(pair)
  raise "wrong shape" unless v.is_a?(Array) && v.size == 2 && v[0].is_a?(Integer) && v[1].is_a?(String)
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(pair)
end
seen # => [[0, ""], [6, "11W1"], [3, "z\u007Fz\u0010~"]]
```

```ruby
generator = composite { |dtc| [dtc.draw_integer(0, 10), dtc.draw_boolean] }
seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(generator)
end
seen # => [[0, false], [6, false], [3, false]]
```

Calling it with no block raises `Hegel::Error` at draw time: `"composite:
block is required"`.

### `deferred`

A forward reference to a generator whose definition is supplied later via
`#set`, enabling self-recursive and mutually recursive generators:

```ruby
tree = deferred
tree.set(one_of(integers(min_value: 0, max_value: 10), arrays(tree, max_size: 3)))

result = Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  v = tc.draw(tree)
  raise "wrong type" unless v.is_a?(Integer) || v.is_a?(Array)
end
result # => nil

seen = []
Hegel.test(test_cases: 3, seed: 1, derandomize: true, verbosity: :quiet) do |tc|
  seen << tc.draw(tree)
end
seen # => [0, [0, []], 4]
```

Drawing from it before `#set` raises `Hegel::Error` at draw time:
`"deferred: draw called before set"`. Calling `#set` a second time raises
immediately (not at draw time): `"deferred: set called more than once"`.

## Stateful Testing

A stateful test compares a real object against a simplified model of it,
across a sequence of actions libhegel chooses and shrinks the same way it
shrinks any other test case. Declare the actions on a `Hegel::StateMachine`
subclass, then drive one instance of it from inside an ordinary `Hegel.test`
block: `Hegel.test { |tc| Hegel::Stateful.run(machine, tc) }` (see
[A worked example](#a-worked-example) below for a complete one).

### Declaring a machine

`rule(name, &block)` and `invariant(name, &block)` are class-level
declarations. `block` runs via `instance_exec` against the machine instance
under test, and is handed the running `Hegel::TestCase` as its one argument
(ignored if the block takes none). So it reads and writes the machine's own
instance variables directly, and calls a generator method (`integers`,
`arrays`, and so on) bare, the same way a `Hegel.test` block's own
surrounding class can once it includes `Hegel::Syntax::Methods`;
`Hegel::StateMachine` already includes that module itself.

An invariant runs once before the first rule, and again after every rule
application that completes without its own assumption failing.

A rule or invariant reports a failure the same way any other test-case body
does: raise. This library brings no assertion methods of its own. Include
`Minitest::Assertions` (or `RSpec::Matchers`, or plain `raise`) into
the machine class to use one. `Minitest::Assertions#assert` counts against
an `assertions` accessor it does not define itself, so a class that includes
it also needs to supply one, initialized to `0`:

```ruby
class AssertingMachine < Hegel::StateMachine
  include Minitest::Assertions
  attr_accessor :assertions

  def initialize
    @assertions = 0
  end

  rule(:step) { |_tc| assert_equal 1, 1 }
end
```

Declaring the same rule or invariant name twice on one class raises
`Hegel::Error`; a subclass declaring a name its superclass already declared
replaces that one instead, keeping its original position in the declared
order. A class with no rule declared at all raises `Hegel::Error`, before
`Hegel::Stateful.run` makes any libhegel call:

```ruby
class NoRulesMachine < Hegel::StateMachine
  invariant(:always) {}
end

# nil stands in for a running Hegel::TestCase here: the check above raises
# before Hegel::Stateful.run reads its second argument at all.
Hegel::Stateful.run(NoRulesMachine.new, nil)
# raises Hegel::Error, "hegel: NoRulesMachine has no rules; declare at least
# one with `rule`"
```

A test case with more than one declared rule enables only a random subset of
them, and picks each step from that subset. So a machine with two rules can
run a case where one of them never appears at all.

Inside a rule, `tc.assume(false)` means something narrower than it does
everywhere else in this library: it discards only that one rule application
(the loop moves on and tries another rule), not the whole test case, unlike
every other `assume` call, such as one at the top of a `Hegel.test` block,
or inside a generator's own draw.

### A worked example

`@real` below never enforces its own capacity. That is the bug a model
capped at 2 items is built to catch:

```ruby
class BoundedStackModel < Hegel::StateMachine
  CAPACITY = 2

  def initialize
    @real = []
    @model_size = 0
  end

  rule(:push) do |tc|
    tc.draw(integers(min_value: 0, max_value: 9))
    @real.push(0) # bug: never checks capacity
    @model_size += 1 if @model_size < CAPACITY
  end

  invariant(:size_matches_capacity) do
    unless @real.size == @model_size
      raise "stack has #{@real.size} items, model expects #{@model_size}"
    end
  end
end

output = StringIO.new
begin
  Hegel.test(output: output, seed: 1, derandomize: true) do |tc|
    Hegel::Stateful.run(BoundedStackModel.new, tc)
  end
rescue RuntimeError => e
  e.message # => "stack has 3 items, model expects 2"
end
output.string
```

```
Falsified after 1 test case (0 discarded):

  Initial invariant check.
  Step 1: push
  draw_1 = 0
  Step 2: push
  draw_2 = 0
  Step 3: push
  draw_3 = 0

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AXiclcaxDQAACMMwd0Xi/3dh4QCGKG6E2tzywQAOIgBh"
```

The shrunk report names each step by its rule (`Step 1: push`), and shrinks
the number of steps down to the minimum that still breaks the invariant.
Here, that is exactly 3 pushes, one past capacity.

### `Hegel::Stateful::Pool`

A pool lets one rule's generated value be drawn again by a later rule,
such as an allocator's handle freed by a rule that has to name the same
handle `alloc` produced. Build one from the running test case, typically in
the machine's own constructor:

```ruby
pool = Hegel::Stateful::Pool.new(tc)
```

- `#add(value)` records `value` under a fresh id, and returns `self`.
- `#values_reusable` is a `Hegel::Generator` over the pool's values that
  leaves the chosen value in place, so it can be drawn again.
- `#values_consumed` is a `Hegel::Generator` over the pool's values that
  removes the chosen value, so it is never drawn again.
- `#size` and `#empty?` read the pool's own count directly.

```ruby
Hegel.test(test_cases: 5, verbosity: :quiet) do |tc|
  pool = Hegel::Stateful::Pool.new(tc)
  raise "a fresh pool must be empty" unless pool.empty?

  pool.add(42)
  raise "a pool holding a value must not be empty" if pool.empty?

  value = tc.draw(pool.values_reusable)
  raise "expected 42, got #{value}" unless value == 42
end
```

Drawing from an empty pool raises `Hegel::AssumeFailed`: outside a rule, that
discards the whole test case, the same as any other failed assumption;
inside a rule, it discards only that rule, the same narrower meaning
`tc.assume(false)` has there. A caller never frees a pool. The test case
that built it owns it, and frees it once that test case is done.

## Combinator Methods

Every `Hegel::Generator`, including every generator above, has `.map`
and `.filter`, each returning a new `Hegel::Generator`.

### `.map(&block)`

Transform drawn values:

```ruby
positive_string = integers(min_value: 1).map { |n| n.to_s }

Hegel.test(test_cases: 10, verbosity: :quiet) do |tc|
  s = tc.draw(positive_string)
  raise "not a digit string" unless s.match?(/\A\d+\z/)
end
```

### `.filter(&block)`

Keep only values matching a predicate:

```ruby
even = integers.filter { |n| n.even? }

Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  n = tc.draw(even)
  raise "not even" unless n.even?
end
```

`.filter` retries its source generator up to 3 times per draw, then
discards the test case. A predicate that (almost) never holds does not loop
forever: libhegel's own health check aborts a run that discards too many
test cases in a row, surfacing as `Hegel::Error`:

```ruby
Hegel.test(test_cases: 20, verbosity: :quiet) do |tc|
  tc.draw(integers.filter { |_n| false })
end
```

raises `Hegel::Error`, message starting `"FailedHealthCheck: FilterTooMuch —
it looks like this test is filtering out too many inputs."` Pass
`suppress_health_check: [:filter_too_much]` (see [Settings](#settings)) to
turn that check off for a filter deliberately built to reject often, or
restructure the generator instead (prefer `.map` over `.filter`, or draw a
value already in the shape you need):

```ruby
result = Hegel.test(test_cases: 20, suppress_health_check: [:filter_too_much], verbosity: :quiet) do |tc|
  tc.draw(integers.filter { |_n| false })
end
result # => nil
```

## Gotchas

1. **`floats` defaults `allow_nan: false, allow_infinity: false`, even when
   fully unbounded.** hegel-rust's and hegel-typescript's `floats()` default
   both to `true` when neither bound is set. This binding always starts
   both off; pass `allow_nan: true` and/or `allow_infinity: true`
   deliberately if the code under test needs to see them.

2. **`integers`'s default range, when a bound is omitted, is still the
   signed 64-bit range (`-2**63..(2**63 - 1)`), even though arbitrary
   precision is available.** Passing both `min_value` and `max_value`
   explicitly draws outside that range at arbitrary precision; leaving one
   bound out still defaults it to `-2**63` or `2**63 - 1`. That default can
   surprise a caller who supplies only one big bound:
   `integers(min_value: 10**30)` raises `Hegel::Error`, `"integers:
   max_value < min_value"`, because `max_value` defaults to `2**63 - 1`,
   smaller than `10**30`. Pass both bounds explicitly to draw a value
   outside the 64-bit range.

3. **Invalid generator options raise at draw time, not at construction
   time.** `integers(min_value: 5, max_value: 1)` builds without error;
   only `tc.draw` on it raises `Hegel::Error`. Every generator in this
   binding follows the same rule, matching hegel-rust's own contract.

4. **`Hegel.test` returns `nil` on a pass and re-raises the failing case's
   own exception on a failure**, class and backtrace intact. A host test
   framework (RSpec, Minitest) reports it as its own failure, not a
   Hegel-specific one.

5. **Failures are grouped by the line they are attributed to, and one
   group is one bug.** The attributed line is the first one in your own
   code: assertions count as failing where you wrote them, not inside
   `minitest` or `rspec-expectations` where the exception is raised. So
   two `assert_equal` failures on different lines are two bugs, and two
   different failures reaching Hegel through one line are one bug. That
   holds whether the line is a ternary or the single `raise` inside a
   helper you wrote. Split the line when two bugs need to stay apart:

   ```ruby
   # one bug: report_multiple_failures: true reports 1 failure
   n.zero? ? raise("boom-zero") : raise("boom-one")

   # two bugs: report_multiple_failures: true reports 2
   if n.zero?
     raise "boom-zero"
   else
     raise "boom-one"
   end
   ```

   The exception's class is left out on purpose: one line raising a
   `NoMethodError` on one input and a `TypeError` on another is still one
   bug.

6. **`verbosity: :quiet` silences the failure report text itself**, not
   just libhegel's own progress output. Even when `output:` is given,
   nothing is written to it on a quiet run.

7. **`database:` without `database_key:` raises `Hegel::Error`
   immediately.** `database_key:` is the setting that turns the example
   database on, and `database:` only chooses where it writes. Left at
   their shared default (`nil`, `nil`), a run stores nothing and leaves no
   `.hegel/` directory behind.

8. **`tc.target` is a silent no-op, not an error, when the `:target` phase
   is disabled.** Dropping `:target` from `phases:` (every other phase
   kept) still lets every `tc.target` call succeed; it just stops
   influencing generation.

9. **Inside a stateful rule, `tc.assume(false)` discards only that one rule
   application, not the whole test case.** See
   [Stateful Testing](#stateful-testing). Every other `assume` call in this
   binding, such as one at the top of a `Hegel.test` block, or inside a
   generator's own draw, discards the whole test case.

10. **The suite runs against the real engine on Linux, macOS, and Windows.**
    Every push to main runs it on Ruby 3.3, 3.4, and 4.0, across Linux x64
    and arm64, macOS arm64, and Windows x64 and arm64. Windows arm64 starts
    at Ruby 3.4, the oldest Ruby that RubyInstaller publishes an arm64 build
    for. Alpine (musl) is the platform this binding has not run on.
