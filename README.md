# Hegel for Ruby

> [!IMPORTANT]
> **This is an unofficial, third-party implementation.** The Hegel project and
> the `libhegel` engine belong to Antithesis, LLC. This repository has no
> affiliation with Antithesis or with the `hegeldev` organization, and nobody
> there reviews or endorses it.
>
> The official implementations are
> [Rust](https://github.com/hegeldev/hegel/tree/main/frontends/rust),
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
same process, through the [`ffi`](https://github.com/ffi/ffi) gem. There is no
server and no Python dependency.

## Installation

The gem is published as [`hegeltest`](https://rubygems.org/gems/hegeltest):

```ruby
# Gemfile
gem "hegeltest", group: :test
```

The require path is `hegel`, and the namespace is `Hegel`.
`require "hegeltest"` also works, so Bundler's automatic require finds it.

The gem needs Ruby 3.4 or later. Each platform gem carries the matching
`libhegel` build, so an install compiles nothing and needs no engine on the
side:

| Platform | Gem platform |
| --- | --- |
| Linux x64 | `x86_64-linux` |
| Linux arm64 | `aarch64-linux` |
| macOS arm64 | `arm64-darwin` |
| Windows x64 | `x64-mingw-ucrt` |
| Windows arm64 | `aarch64-mingw-ucrt` |

The Hegel maintainers permit a third-party project to redistribute their
release binaries ([hegeldev/hegel-rust#411]).

A project that already has a `Gemfile.lock` needs one more step. Bundler adds
only the platform of the machine that runs `bundle install`, so a lock made on
a Mac does not name Linux. A Linux CI job then cannot find the gem. Add each
platform your CI uses:

```bash
bundle lock --add-platform x86_64-linux
```

On a platform with no published `libhegel` build, such as macOS on Intel, build
the engine yourself and set `HEGEL_LIBHEGEL_PATH` to the library file or to the
directory that holds it. The same variable makes any platform use a local
engine build in place of the bundled one.

[hegeldev/hegel-rust#411]: https://github.com/hegeldev/hegel-rust/issues/411

### Which libhegel a release carries

Each gem release pins one libhegel release. To see the pinned version in your
installed gem:

```bash
ruby -rhegel -e 'puts Hegel::LIBHEGEL_VERSION'
```

The [CHANGELOG](CHANGELOG.md) section of each gem release starts with the
engine move, when there is one, and links the release notes of that engine
version. The [GitHub releases](https://github.com/meganemura/hegel-ruby/releases)
show the same text.

When libhegel publishes a new release, a pull request moves this gem to it.
The gem version and the engine version are independent: a gem release can
change the engine, the Ruby code, or both.

## Quickstart

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
still shows the bug. The report looks like this:

```
Falsified after 11 test cases (0 discarded):

  xs = [0, 0]

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ=="
```

The count of test cases and the blob change from run to run, and between
engine releases. The shrunk value is the part to read: two duplicates are all
it takes. Hegel names the value `xs` by reading the line the draw was written
on. Then it re-raises RSpec's own expectation failure, so RSpec reports it as
its own.

Including `Hegel::Syntax::Methods` makes the generators available without a
prefix, the way FactoryBot makes `create` available. The same generators are
also available as `Hegel::Generators.arrays(...)` without the include.

To keep the generator names out of example groups that have their own
helpers, include the methods only in tagged groups:

```ruby
config.include Hegel::Syntax::Methods, :hegel
```

Hegel draws values imperatively, so an ordinary Ruby method can share a group
of draws between properties. Give the method parameter a descriptive name,
which the default RuboCop naming rule accepts:

```ruby
def draw_sorted_pair(test_case)
  low = test_case.draw(integers(min_value: 0, max_value: 100))
  high = test_case.draw(integers(min_value: low, max_value: 200))
  [low, high]
end

Hegel.test do |tc|
  low, high = draw_sorted_pair(tc)
  expect(low).to be <= high
end
```

### Minitest

Hegel needs nothing from your test framework. Include the generator methods
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

Minitest reports the shrunk case as its own assertion failure, at your line:

```
1) Failure:
MySortTest#test_matches_the_builtin_sort [test/my_sort_test.rb:5]:
Expected: [0, 0]
  Actual: [0]
```

## Generators

| Kind | Generators |
| --- | --- |
| Numbers and booleans | `integers`, `floats`, `booleans` |
| Text and bytes | `text`, `characters`, `binary`, `from_regex`, `from_lark` |
| Collections | `arrays`, `sets`, `hashes`, `tuples` |
| Choice | `just`, `sampled_from`, `permutations`, `subsequences`, `samples`, `one_of`, `optional` |
| Formats | `emails`, `urls`, `domains`, `ip_addresses`, `uuids` |
| Time | `dates`, `times`, `datetimes`, `date_strings`, `time_strings`, `datetime_strings`, `durations` |
| Your own | `composite`, `deferred` |

Each one composes through `map` and `filter`. Options are keywords, with the
names the other Hegel implementations use, such as
`integers(min_value: 0, max_value: 9)`, `arrays(text, max_size: 5)`, or `arrays(integers, unique: true)`. An
invalid combination of options raises when the generator is drawn, not when it
is built.

## Stateful testing

Some bugs need a sequence of operations rather than one input. Declare the
operations as rules on a `Hegel::StateMachine`. Hegel picks which rule runs
next, checks your invariants along the way, and shrinks a failure to the
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
rather than throwing the whole test case away. When a rule must act on a value
that an earlier rule made, such as freeing a handle that some `alloc` returned,
put the value in a `Hegel::Stateful::Pool` and draw it back out.

Every invariant runs before the first rule and after the last. Between rules,
the engine samples each invariant. Declare an invariant with
`always_run: true` to check it after every rule.
`Hegel::Stateful.run(machine, tc, step_count: 50)` sets the largest number of
rules that one test case runs; 50 is the default.

## Configuring a run

`Hegel.test` takes these keywords:

| Keyword | Effect |
| --- | --- |
| `profile` | The settings profile the run starts from; see [Profiles](#profiles) |
| `test_cases` | How many test cases to generate |
| `seed` | The seed for the random generation |
| `derandomize` | Make the generation deterministic |
| `verbosity` | How much the engine prints; `:quiet` also hides the failure report |
| `phases` | Which engine phases run, such as generation and shrinking |
| `suppress_health_check` | Which health checks to turn off |
| `report_multiple_failures` | Report each distinct failure; `false` by default |
| `stop_on_first_failure` | `false` spends the whole `test_cases` budget before reporting |
| `print_blob` | `false` leaves the reproduction line out of the failure report |
| `show_statistics` | Print what `tc.event` and `tc.event_value` recorded, at the end of the run |
| `nondeterminism_strictness` | `:quiet`, `:warn`, or `:error` when the test behaves differently on a replay |
| `backend` | `:default`, or `:urandom` to take fresh entropy on every draw, for Antithesis |
| `database_key` | Turn the example database on for this property |
| `database` | The directory of the example database |
| `reproduce_failure` | Replay one failure from the blob in its report |

A keyword that you do not set takes its value from the engine's settings
profile. That is libhegel's own default, unless a `hegel.toml` file or a
`HEGEL_*` environment variable changes it. On a CI server the engine uses its
`ci` profile, which derandomizes the run and turns the example database off.

The example database stores a failing case and replays it first next time.
`database_key` turns it on, and `database` chooses the directory:

```ruby
Hegel.test(database_key: "my_sort matches the builtin sort") { |tc| ... }
```

Give each property its own key. See
[ADR 0009](docs/adr/0009-turn-the-example-database-on-with-a-key.md) for why
the key, and not the directory, turns it on.

Inside a test, `tc.note` records a message that the failure report prints, and
`tc.target` tells Hegel which inputs to search toward.

`tc.event` and `tc.event_value` check that a test reaches the cases you care
about. With `show_statistics: true`, the engine prints how often each event
happened and a summary of each value. The numbers change from run to run:

```ruby
Hegel.test(show_statistics: true) do |tc|
  xs = tc.draw(arrays(integers))
  tc.event("empty") if xs.empty?
  tc.event_value("size", xs.size)
end
```

```
Statistics (over 100 test cases):
  * empty: 6.0% of test cases
  * size: count 100, min 0, median 6, mean 7.99, p90 19, max 20
```

## Profiles

A profile is a named set of settings. The engine ships `development`, `ci`,
and `workload`, and a `hegel.toml` file can define more. Pass `profile:` to
start one run from a profile, and register your own with
`Hegel::Settings.register_profile`:

```ruby
Hegel::Settings.register_profile("nightly", profile: "ci", test_cases: 10_000)

Hegel.test(profile: "nightly") { |tc| ... }
```

A keyword passed to `Hegel.test` still beats the profile. A profile you
name extends the default profile, so what it does not set comes from
there. `Hegel::Settings.set_default_profile("nightly")` makes a profile the
default for every run in the process, and `set_default_profile("")` clears
it. Registration and the default are process-wide, and they do not change
runs that have already started. `register_profile` takes the keywords of
`Hegel.test` except `database_key`, which a profile does not carry, and
`Hegel.test` always passes `report_multiple_failures`, so a profile's value
for it never applies. An unknown name raises `Hegel::Error`. See
[ADR 0028](docs/adr/0028-expose-settings-profiles-as-a-keyword-and-module-functions.md).

## Agent skill

Two skills work together. The official
[hegel-skill](https://github.com/hegeldev/hegel-skill) from the Hegel
maintainers teaches the method: which properties to look for, and how to
check the tests an agent writes. It works with every Hegel implementation.
[`skills/hegel-ruby`](skills/hegel-ruby/SKILL.md) adds the Ruby part: this
gem's API and how to use it with RSpec and Minitest. Install both.

In Claude Code, add each repository as a marketplace and install its plugin:

```
/plugin marketplace add hegeldev/hegel-skill
/plugin install hegel-skill@hegeldev
/plugin marketplace add meganemura/hegel-ruby
/plugin install hegel-ruby@meganemura
```

For Codex and other agents, see the installation section of the
[hegel-skill README](https://github.com/hegeldev/hegel-skill#installation).
For this gem's skill, use the same steps with
<https://github.com/meganemura/hegel-ruby/tree/main/skills/hegel-ruby>.

## Development

```bash
bin/setup                        # install dependencies
bundle exec rake libhegel:fetch  # download the pinned engine, checked against its SHA-256
bundle exec rake                 # run the tests with coverage, and the linter
bundle exec rake mutation        # run mutation testing
bin/console                      # open an interactive prompt
```

`just` recipes call the same Rake tasks, so `just check`, `just test`, and
`just lint` work for anyone who uses `just` with the other Hegel
implementations.

CI runs the suite on each pull request and on each push to main, on every
platform in the table above, with Ruby 3.4 and 4.0.

The design records are in [docs/](docs/README.md).

### Releasing

A merge into main that changes `lib/hegel/version.rb` starts a release. The
Release workflow waits for an approval of the `release` environment. After
the approval, it runs the tests, publishes the gems to RubyGems, and then
creates the tag `v<version>` and the GitHub release. The release notes come
from the version's section of [CHANGELOG.md](CHANGELOG.md). See
[ADR 0024](docs/adr/0024-release-when-a-merge-changes-the-gem-version.md).

## Contributing

Report bugs and open pull requests at
<https://github.com/meganemura/hegel-ruby>. Contributors follow the
[code of conduct](CODE_OF_CONDUCT.md).

## License

This gem is available under the [MIT License](LICENSE.txt).

Released gems also carry `libhegel`'s own license, which is MIT and copyright
Antithesis, LLC. Each platform gem ships `NOTICE-libhegel.txt` next to the
engine, and that file holds the text.

---

[日本語版 README](README.ja.md)
