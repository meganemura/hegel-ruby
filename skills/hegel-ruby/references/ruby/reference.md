# Hegel Ruby Reference

## Table of Contents

- [Setup](#setup)
- [Test Structure](#test-structure) — `Hegel.test`, its block, return value, failure behavior
- [Settings](#settings) — `test_cases:` `seed:` `derandomize:` `verbosity:` `output:` `reproduce_failure:`
- [TestCase Methods](#testcase-methods) — `draw`, `draw_integer`, `draw_boolean`
- [Generator Reference](#generator-reference) — `booleans`, `integers`, `floats`, `text`, `arrays`
- [Combinator Methods](#combinator-methods) — `.map`, `.filter`
- [Gotchas](#gotchas)

## Setup

Hegel for Ruby ships as the `hegeltest` gem. It has not reached RubyGems.org
yet (the project is pre-release, at version `0.0.0`); until it does, point a
Gemfile at the repository directly:

```ruby
# Gemfile
gem "hegeltest", git: "https://github.com/meganemura/hegel-ruby"
```

Require it, then include the generator methods wherever tests draw values:

```ruby
require "hegel"

include Hegel::Syntax::Methods
```

`Hegel::Syntax::Methods` makes the generator methods (`booleans`, `integers`,
`floats`, `text`, `arrays`) callable bare, the way FactoryBot's own
`Syntax::Methods` makes `create` callable bare. With Minitest, include it
once on the base test class:

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
run the code under test, and signal a failure by raising — any uncaught
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
| `test_cases` | `Integer` or `nil` | `nil` (libhegel's own default) | Number of test cases to run |
| `seed` | `Integer` or `nil` | `nil` (libhegel picks its own) | Fixed RNG seed; pair with `derandomize: true` for a reproducible sequence |
| `derandomize` | `true`/`false` or `nil` | `nil` (libhegel's own default) | Derive the seed deterministically from the test itself, instead of drawing a random one |
| `verbosity` | `Symbol` or `nil` | `nil` (libhegel's own default) | `:quiet`, `:normal`, `:verbose`, or `:debug` |
| `output` | `IO` | `$stderr` | Where a failure report is written |
| `reproduce_failure` | `String` or `nil` | `nil` | Replays the single case the blob encodes, instead of running a full property |

`nil` means the same thing for `test_cases`, `seed`, `derandomize`, and
`verbosity`: do not call the matching libhegel setter, and let the engine's
own default apply.

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
libhegel's own progress output — even when `output:` is given, nothing is
written to it.

## TestCase Methods

| Method | Signature | Purpose |
|---|---|---|
| `draw` | `draw(generator, label: nil)` | Draw a value from a `Hegel::Generator`; shown in the failure report under `label`, or a name recovered from the caller's own source line |
| `draw_integer` | `draw_integer(min_value, max_value, label: nil)` | Draw an integer directly, without building an `integers` generator |
| `draw_boolean` | `draw_boolean(p = 0.5, label: nil)` | Draw a boolean directly, without building a `booleans` generator |

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

`assume` and `note` — `TestCase` methods other Hegel bindings expose — are
not available yet; they arrive in a later milestone. Today, `.filter` (see
[Combinator Methods](#combinator-methods)) discards a test case when its
predicate does not hold.

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

An integer in `[min_value, max_value]`, defaulting to the full signed
64-bit range (`-2**63..(2**63 - 1)`) when either bound is omitted.

```ruby
Hegel.test(test_cases: 30, verbosity: :quiet) do |tc|
  n = tc.draw(integers(min_value: 0, max_value: 100))
  raise "out of range" unless n.between?(0, 100)
end
```

`max_value < min_value` raises `Hegel::Error` at draw time:
`"integers: max_value < min_value"`. A bound outside the 64-bit range also
raises at draw time: `"integers: bounds outside the 64-bit range are not
supported yet"`. Arbitrary-precision integers arrive in milestone B.

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
expose) arrive in milestone B.

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
elements, useful for key generation) arrives in milestone B, as do `sets`,
`hashes`, `tuples`, and `sampled_from`.

## Combinator Methods

Every `Hegel::Generator` — including the five above — has `.map` and
`.filter`, each returning a new `Hegel::Generator`.

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
it looks like this test is filtering out too many inputs."` Suppressing
individual health checks (`suppress_health_check:` in other Hegel bindings)
arrives in a later milestone; today, restructure the generator instead
(prefer `.map` over `.filter`, or draw a value already in the shape you
need).

## Gotchas

1. **`floats` defaults `allow_nan: false, allow_infinity: false`, even when
   fully unbounded.** hegel-rust's and hegel-typescript's `floats()` default
   both to `true` when neither bound is set. This binding always starts
   both off; pass `allow_nan: true` and/or `allow_infinity: true`
   deliberately if the code under test needs to see them.

2. **`integers` only covers the signed 64-bit range.** A bound outside
   `-2**63..(2**63 - 1)` raises `Hegel::Error` at draw time. Arbitrary
   precision integers arrive in milestone B.

3. **Invalid generator options raise at draw time, not at construction
   time.** `integers(min_value: 5, max_value: 1)` builds without error;
   only `tc.draw` on it raises `Hegel::Error`. Every generator in this
   binding follows the same rule, matching hegel-rust's own contract.

4. **`tc.assume` and `tc.note` are not available yet.** They arrive in a
   later milestone. `.filter` discards a test case today when its predicate
   does not hold.

5. **`Hegel.test` returns `nil` on a pass and re-raises the failing case's
   own exception on a failure**, class and backtrace intact — a host test
   framework (RSpec, Minitest) reports it as its own failure, not a
   Hegel-specific one.

6. **`verbosity: :quiet` silences the failure report text itself**, not
   just libhegel's own progress output. Even when `output:` is given,
   nothing is written to it on a quiet run.

7. **This binding always disables libhegel's example database.** There is
   no `database:` setting to pass yet, and no `.hegel/` directory to manage
   in a project that uses this gem.

8. **Only five generators exist today: `booleans`, `integers`, `floats`,
   `text`, and `arrays`.** `sets`, `hashes`, `tuples`, `sampled_from`,
   `composite`, `record`, format generators (emails, URLs, dates), stateful
   testing, and targeted testing all arrive in later milestones.
