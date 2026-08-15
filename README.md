# Hegel for Ruby

> [!IMPORTANT]
> **This is an unofficial, third-party implementation.** The Hegel project and
> the `libhegel` engine belong to Antithesis, LLC. This repository has no
> affiliation with Antithesis or with the `hegeldev` organization, and nobody
> there reviews or endorses it.
>
> The official implementations are
> [Rust](https://github.com/hegeldev/hegel-rust),
> [Go](https://github.com/hegeldev/hegel-go),
> [C++](https://github.com/hegeldev/hegel-cpp),
> [TypeScript](https://github.com/hegeldev/hegel-typescript),
> [Java](https://github.com/hegeldev/hegel-java), and
> [OCaml](https://github.com/hegeldev/hegel-ocaml). Report problems with this
> gem here, not to them.

> [!NOTE]
> Hegel itself is in beta, and its maintainers expect to make breaking changes.
> See <https://hegel.dev/compatibility>.

Hegel is a property-based testing framework based on
[Hypothesis](https://github.com/hypothesisworks/hypothesis). Instead of writing
tests with hand-picked inputs, you state a property that must hold for every
input. Hegel generates inputs, tries to falsify the property, and shrinks any
failure to a minimal counterexample.

This gem drives [libhegel](https://hegel.dev/reference/libhegel), the native
engine that the official implementations also drive. The engine runs in the
same process. There is no server and no Python dependency.

## Status

**Nothing is released yet, and the version stays at `0.0.0` until it is.**
Everything described below runs: Hegel finds a counterexample, shrinks it,
names the values it drew, and re-raises your own exception.

Work ran in three stages, and all three are done:

1. **The walking skeleton** — the libhegel binding, the run loop, and failure
   reports.
2. **The full generator set** — twenty-five generators, composing through
   `map` and `filter`.
3. **The advanced features** — the example database, targeted testing,
   stateful testing, phases, and health checks.

What is left before the first release to RubyGems.org is a measurement rather
than a feature: [ADR 0008](docs/adr/0008-revisit-the-binding-after-milestone-c-on-measurement.md)
schedules a comparison of `fiddle` against the `ffi` gem now that the whole
binding surface exists.

Building this repository needs the engine on hand. `rake libhegel:fetch`
downloads the pinned build and checks it against its published SHA-256.

## Design

| Decision | Choice |
| --- | --- |
| Gem name | `hegeltest` |
| Require path | `require "hegel"` (`require "hegeltest"` also works) |
| Namespace | `Hegel` |
| Binding | `fiddle`, so installing the gem needs no compiler |
| Ruby | 3.3, 3.4, and 4.0 |
| Platforms | Linux amd64/arm64, macOS arm64, Windows amd64/arm64 |
| Engine delivery | One prebuilt `libhegel` per platform-specific gem |

`HEGEL_LIBHEGEL_PATH` will override the bundled engine with a local build.

The gem name follows the Rust implementation, whose published crate is
`hegeltest` and whose library is `hegel`. The name `hegel` on RubyGems.org
stays free for whoever publishes an official Ruby implementation.

macOS on Intel has no published `libhegel` artifact, so that platform will need
`HEGEL_LIBHEGEL_PATH` and a local build.

## Quickstart

Everything below runs today.

```ruby
# spec/spec_helper.rb
require "hegel"

RSpec.configure do |config|
  config.include Hegel::Syntax::Methods
end
```

```ruby
# spec/my_sort_spec.rb
def my_sort(ls) = ls.sort.uniq # oops: uniq drops duplicates

RSpec.describe "my_sort" do
  it "matches the builtin sort" do
    Hegel.test do |tc|
      xs = tc.draw(arrays(integers))
      expect(my_sort(xs)).to eq(xs.sort)
    end
  end
end
```

That test fails, and Hegel shrinks the failure to the smallest input that
still shows the bug:

```
Falsified after 11 test cases (0 discarded):

  xs = [0, 0]

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ=="
```

Two duplicates are all it takes. Hegel names the value `xs` by reading the
line the draw was written on, then re-raises RSpec's own expectation failure,
so the framework reports it as its own.

Including `Hegel::Syntax::Methods` makes the generators available without a
prefix, the way FactoryBot makes `create` available. The same generators stay
reachable as `Hegel::Generators.arrays(...)` without the include.

The generators are `arrays`, `binary`, `booleans`, `characters`, `composite`,
`dates`, `datetimes`, `deferred`, `domains`, `emails`, `floats`, `from_regex`,
`hashes`, `integers`, `ip_addresses`, `just`, `one_of`, `optional`,
`sampled_from`, `sets`, `text`, `times`, `tuples`, `urls`, and `uuids`. Each
one composes through `map` and `filter`.

### Minitest

Hegel needs nothing from your test framework. Install the generator methods
once, and write the property inside an ordinary test:

```ruby
# test/test_helper.rb
require "hegel"

class Minitest::Test
  include Hegel::Syntax::Methods
end
```

```ruby
# test/my_sort_test.rb
class MySortTest < Minitest::Test
  def test_matches_the_builtin_sort
    Hegel.test do |tc|
      xs = tc.draw(arrays(integers))
      assert_equal xs.sort, my_sort(xs)
    end
  end
end
```

Minitest reports the shrunk case as its own assertion failure, pointing at
your line:

```
1) Failure:
MySortTest#test_matches_the_builtin_sort [test/my_sort_test.rb:5]:
Expected: [0, 0]
  Actual: [0]
```

### Stateful testing

Some bugs need a sequence of operations rather than one input. Declare the
operations as rules on a `Hegel::StateMachine`, and Hegel picks which runs
next, checks your invariants after each one, and shrinks a failure to the
shortest sequence that still shows it:

```ruby
class StackMachine < Hegel::StateMachine
  def initialize
    @stack = BoundedStack.new(3)
    @model = []
  end

  rule :push do |tc|
    x = tc.draw(integers(min_value: 0, max_value: 9))
    @stack.push(x)
    @model.push(x) if @model.size < 3
  end

  rule :pop do |tc|
    tc.assume(!@model.empty?)
    raise "pop disagreed" unless @stack.pop == @model.pop
  end

  invariant :size_agrees do
    raise "size disagreed" unless @stack.size == @model.size
  end
end

Hegel.test { |tc| Hegel::Stateful.run(StackMachine.new, tc) }
```

`tc.assume` inside a rule rejects that rule and lets Hegel choose another,
rather than throwing the whole test case away. For a rule that has to act on
something an earlier rule produced — freeing a handle that some `alloc`
actually returned — put the value in a `Hegel::Stateful::Pool` and draw it
back out.

### Shaping a run

`Hegel.test` takes keywords for the rest: `test_cases`, `seed`,
`derandomize`, `verbosity`, `phases`, `suppress_health_check`,
`report_multiple_failures`, and `stateful_step_count`. Each one left unset
means the engine's own default.

Two more turn on libhegel's example database, which stores a failing case and
replays it first next time. `database_key` is the switch and `database`
chooses the directory:

```ruby
Hegel.test(database_key: "my_sort matches the builtin sort") { |tc| ... }
```

Give each property its own key. See
[ADR 0009](docs/adr/0009-turn-the-example-database-on-with-a-key.md) for why
the key, rather than the directory, is what turns it on.

Inside a test, `tc.note` records a message the failure report prints, and
`tc.target` tells Hegel which inputs to search toward.

## Development

```bash
bin/setup          # install dependencies
bundle exec rake   # run the tests and the linter
bin/console        # open an interactive prompt
```

`just` recipes call the same Rake tasks, so `just test` and `just lint` work
for anyone who already uses `just` with the other Hegel implementations.

## Contributing

Report bugs and open pull requests at
<https://github.com/meganemura/hegel-ruby>. Contributors follow the
[code of conduct](CODE_OF_CONDUCT.md).

## License

This gem is available under the [MIT License](LICENSE.txt).

Released gems will also carry the license of `libhegel`, which is MIT and
copyright Antithesis, LLC, together with the licenses of the Rust crates that
`libhegel` links.
