# 0018: Gate mutation testing on a committed baseline

## Status

Accepted. It builds on
[ADR 0016](0016-run-mutation-testing-with-mutineer.md).

## Context

ADR 0016 runs mutineer over `lib/`: 706 mutants in about a minute, with 153
survivors. Nothing checked the result, so a change could add a survivor and
no one would see it.

mutineer has two ways to narrow what fails a run. `--since REF` mutates only
the lines changed since `REF`. `--baseline FILE` compares the run with an
earlier JSON report, and fails on a survivor whose stable id is not in the
report, or on a lower score. The id does not depend on the line number.

mutineer writes its JSON report on one line of about 55 KB. Committed as it
is, a change to the survivors reads as one changed line in a pull request.

## Decision

`test/mutation-baseline.json` holds the accepted survivors, and CI fails on
any other survivor:

- `rake mutation` runs over all of `lib/` with `--baseline` on that file.
  `rake mutation:baseline` rewrites the file from a full run.
- The file keeps what `--baseline` reads: `schema_version`, `summary.score`,
  `summary.scoped`, and each survivor's `id`. Each survivor is one line,
  sorted by file, method, and id, with the mutated line before and after. It
  leaves out line numbers.
- `--baseline-epsilon 1` absorbs a small score drop. A mutant that times out
  on a slow machine leaves the score, and it can never add a survivor.
- The CI job `mutation` runs `rake mutation` once, on Linux with Ruby 4.0, for
  every push and pull request.
- `rake mutation:baseline` refuses a `--since` run, which mutineer refuses as
  a baseline too. It also refuses to write a file that contains the working
  directory or the home directory, because the file is public.

A full run takes about a minute, so CI runs in full. `--since` stays for a
local run on a change in progress.

Two alternatives were refused:

- A baseline made on main by CI and passed to a pull request as an artifact.
  It adds no file to the repository, but a reviewer cannot see a change to the
  survivors, and the workflow needs to find the artifact of the right run.
- A gate on `--since` alone, which fails on any survivor on a changed line. An
  edit to a line with an old survivor would then fail for a survivor that the
  edit did not add.

## Consequences

A pull request that adds a survivor fails, until it adds a test or accepts
the survivor with `rake mutation:baseline`. The accepted survivor then shows
as one added line in the diff. A pull request that kills a survivor passes
without a change to the file, and the next rewrite shows the survivor as one
removed line.

A survivor that no test can kill, because the mutant behaves the same as the
original, belongs in `.mutineer.yml` under `ignore:`, with its reason in a
comment beside the id. It then leaves the baseline too.
