---
name: self-review
description: "Review your own changes before you open a pull request or call the work done. Use it when a chunk of work is finished, before creating a PR, or when asked to review changes."
---

# Self-Review

Catch what a reviewer would flag, before they have to.

## Run the checks

```bash
bundle exec rake                          # tests and linter
mise exec ruby@3.3.12 -- bundle exec rake # the oldest supported Ruby
```

Fix every failure before going on. Run them again even when they passed an hour
ago, because the code has changed since.

The second command matters when the diff touches a test. This gem supports
Ruby 3.3 through 4.0, and a test written against a newer Ruby's API passes
here and errors there — `Exception#set_backtrace` takes
`Thread::Backtrace::Location` objects from 3.4 on and raises `TypeError` on
3.3. That shape does not announce itself as a version problem: the errored
test takes its branch's coverage with it, so CI reports a coverage shortfall
on one Ruby and says nothing about why.

## Read the diff

Run `git diff main...HEAD` and read it. Look for:

- **Dead code.** Unused requires, methods left behind by a refactor, a constant
  nothing reads.
- **Tests that mirror the implementation.** A test with the same branches as
  the code it covers still passes after you introduce a bug. Name the bug each
  test would catch; if you cannot, the test is decoration.
- **Network calls in tests.** The library never touches the network, and the
  tests should not either. Downloads belong to the development Rake task.
- **Hardcoded paths.** `/tmp/foo` in a test should be `Dir.mktmpdir`, so that
  two runs cannot collide.
- **Comments that say what instead of why.** The code already says what. A
  comment earns its place by recording a constraint or an alternative that got
  rejected.
- **Claims that rest on absence.** "Only here", "nothing else does this",
  "no other implementation states it". A search tells you where something is
  and never tells you that you found all of it. Write the positive relation
  instead: name the file that does say the thing.
- **Citations of documents that are not in the repository.** Run this, and
  read every line it prints:

  ```bash
  git grep -nE "decision record|task'?-?s own|the spec\b|spec\.md|task-spec|as specified|this batch|working note" -- lib test sig docs skills README.md CHANGELOG.md
  ```

  A comment reading "see the task's own decision record" is a broken link
  for anyone who clones this repository, and it sits exactly where the
  reason should be. The fix is never to reword the citation. Write the
  reason in place, and keep the citation only when it names a path this
  repository carries:

  ```ruby
  # This layer does not validate version itself (see the task's own    # no
  # decision record).

  # This layer does not validate version itself: hegel_generate_uuid    # yes
  # rejects a value outside its documented 0..15 range, and
  # LibHegel.check! translates that into this Hegel::Error. Checking it
  # here as well would mean two messages for one mistake.
  ```

  The grep matters because reading for this does not catch it: nine of
  these shipped across four batches while this section already asked the
  question in prose. Most were one clause away from being complete
  already, which is what makes them so easy to read past.
- **New coverage exclusions.** Each one needs permission and a written reason.
  See the `coverage` skill.

## Check this project's standing constraints

CLAUDE.md states these. This is where you confirm the diff honours them.

- Does anything outside the libhegel binding module name `FFI::`?
- Does every native handle the diff allocates get freed in an `ensure`?
- Do the control exceptions still descend from `Exception` rather than
  `StandardError`? Would a `rescue => e` in a user's test body swallow any of
  them?
- Does every compound generator wrap its draws in a span?
- Does every new generator validate at draw time rather than at build time?
- Do the new validation messages read as public API, with a stable substring a
  test can assert against?

## For a new generator

The full test set lives in hegel-rust's `new-generator` skill, at
`.agents/skills/new-generator/SKILL.md` in that repository. A generator needs a
sanity test, one test per option, a test that composes it inside `arrays`, and
one test per validation. That skill also says not to add explicit edge-case
tests, so do not.

## Last pass

Read the diff as though somebody else wrote it. What would you say in review?
Usual catches: a method that raises where it should return, a wrapper that
exists only to be testable and then is not tested, an error message that names
the problem without telling the reader how to fix it.
