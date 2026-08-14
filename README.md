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

**Nothing is released yet, and the version stays at `0.0.0` until it is.** The
walking skeleton runs: Hegel finds a counterexample, shrinks it, names the
values it drew, and re-raises your own exception.

Work runs in three stages:

1. **The walking skeleton** — done. The libhegel binding, the run loop, failure
   reports, and the `booleans`, `integers`, `floats`, `text`, and `arrays`
   generators.
2. **The full generator set** — the remaining generators and combinators.
3. **The advanced features** — the example database, targeted testing, stateful
   testing, phases, and health checks.

The first release to RubyGems.org comes after stage 3.

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

Today's generators are `booleans`, `integers`, `floats`, `text`, and `arrays`,
and each one composes through `map` and `filter`.

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
