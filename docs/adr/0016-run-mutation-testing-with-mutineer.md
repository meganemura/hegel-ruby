# 0016: Run mutation testing with mutineer

## Status

Accepted.

## Context

The suite holds line and branch coverage at 100%. Coverage shows that a line
ran. It does not show that a test would notice a change to that line.
Mutation testing measures that: it changes the source in small ways, one at
a time, and runs the tests against each change.

mutineer is a mutation testing tool for Ruby. It parses the source with
Prism and has no runtime dependency. It runs Minitest, and it selects, for
each mutant, the test files that cover the mutated line.

A first run over `lib/` met four problems, all measured on mutineer 1.0.2:

- mutineer puts only `lib/` on the load path. Every test file starts with
  `require "test_helper"`, so each one failed to load. The run then reported
  every mutant as uncovered, with a score of N/A and exit status 0. The load
  error appears only with `--verbose`.
- mutineer pairs a source with `test/<name>_test.rb` only. This suite
  names its tests `test_<name>.rb`, so each test file must be named with
  `--test`. The flag takes one file, and it repeats. A first run gave one
  flag several files, and the files after the first became sources to
  mutate, so the score read 0.7%.
- mutineer replaces `$stdout` with a `StringIO` before it runs the tests.
  Minitest's `capture_subprocess_io` reopens `$stdout` on a file, so
  `test/hegel/test_conformance.rb` failed before any mutant ran.
- mutineer runs every mutant's tests in this one working directory. A
  mutant that wrote `./.hegel` left the directory in place, and the
  teardown check in five test classes then failed the tests of every later
  mutant too.

## Decision

`bundle exec rake mutation` (and `just mutation`) runs mutineer 1.0.2 over
`lib/`, with four settings:

1. `RUBYOPT` gets `-Itest`, so `require "test_helper"` resolves.
2. Each test file gets its own `--test` flag.
3. `test/hegel/test_conformance.rb` stays out of the run. It still runs in
   `rake test`.
4. `--strategy redefine`. mutineer's default, `reload`, loads the whole
   mutated file from a tempfile by a relative path, so its backtrace lines
   show a relative path. `Hegel::Runner.origin_for` then takes a line in
   `lib/` for the caller's, and its test fails for every mutant of
   `lib/hegel/test_case.rb`. That alone killed three mutants that the
   suite does not catch: one of them, applied by hand, left all 377 tests
   passing. `redefine` loads only the mutated method.

The five teardowns share `HegelDirectoryGuard#refute_new_hegel_directory`
(`test/test_helper.rb`). When a test leaves a `./.hegel` it did not find at
the start, the guard removes the directory, then fails the test. The mutant
that wrote it is still killed, and later mutants no longer fail on the
leftover. A `./.hegel` that existed before the test stays in place.

`mutineer` is a development dependency, pinned exact and never required at
load time. It needs Ruby 3.4 or later, and the gem supports 3.3, so it sits
in the Gemfile group `mutation`. CI leaves that group out on every job, and
a 3.3 install leaves it out with `bundle config set --local without
mutation`. Mutation testing then runs on 3.4 or later only.
`.mutineer/` (the cache and reports) and `.hegel/` are ignored by git.

## Consequences

The run over `lib/` covers 706 mutants in about a minute: 539 killed, 153
survived, 8 without coverage, 6 without a verdict, a score of 77.9%. Measured
with the reload strategy, the guard alone turned 10 former kills into
survivors, which were false kills before.

The survivors are a list of tests to add. A later change works through them
by file.

Settings 1, 3, and 4 work around mutineer itself, and setting 2 follows
from its pairing rule. Each is reported: the load path as
[davidteren/mutineer#119](https://github.com/davidteren/mutineer/issues/119),
the pairing rule as
[davidteren/mutineer#120](https://github.com/davidteren/mutineer/issues/120),
the `StringIO` as
[davidteren/mutineer#121](https://github.com/davidteren/mutineer/issues/121),
and the relative path as
[davidteren/mutineer#123](https://github.com/davidteren/mutineer/issues/123).
When a mutineer release fixes one, drop the setting that it replaces.
