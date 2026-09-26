# 0017: Raise the Ruby floor to 3.4

## Status

Accepted. Supersedes the Gemfile group `mutation` in the Consequences of
[ADR 0016](0016-run-mutation-testing-with-mutineer.md).

## Context

The gem supported Ruby 3.3, 3.4, and 4.0. Ruby 3.3 has had security
maintenance only since 2026-04-01, and its end of life is expected on
2027-03-31.

mutineer 1.0.2, the mutation testing tool of ADR 0016, needs Ruby 3.4 or
later. With mutineer in the Gemfile, `bundle install` failed on every 3.3 job
in CI. The first fix put mutineer in a Gemfile group `mutation`. Every CI job
left that group out, and a developer on 3.3 had to leave it out by hand. That
fix gave the repository two install paths, and CI never installed a tool that
the repository runs.

## Decision

The floor is Ruby 3.4:

- `required_ruby_version` is `>= 3.4.0`.
- CI runs Ruby 3.4 and 4.0.
- `.standard.yml` targets Ruby 3.4.
- mutineer is back in the default Gemfile group, and CI installs it.

Keeping 3.3 with the group was refused, because of the two install paths above.

## Consequences

A project on Ruby 3.3 stays on 0.1.1, the last release that installs there.
The next release says so in the changelog.

Every CI job installs the same bundle, and a developer needs one Ruby for the
gem and its tools. The matrix loses its one exclusion: RubyInstaller has an
arm64 Windows build for every Ruby in it.

ADR 0001, ADR 0005, and ADR 0008 name 3.3 as the floor, which it was when
they were written. ADR 0005's reason still holds on 3.4: Ruby 3.4 also ships
Prism as a default gem.
