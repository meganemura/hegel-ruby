# 0024: Release when a merge changes the gem version

## Status

Accepted. Replaces the tag push that started the Release workflow.

## Context

A release took three steps from the maintainer: merge the pull request that
prepares the version, push the tag `v<version>` on the merged commit, and
approve the `release` environment. The tag carried no decision of its own.
The version in `lib/hegel/version.rb` already said what to release, and the
approval was the real gate.

A daily routine now opens a pull request for each new libhegel release, with
a "Prepare <version>" commit. The maintainer's part should be the decision,
not the steps around it.

GitHub does not start a workflow from a push that a workflow makes with its
own `GITHUB_TOKEN`. A workflow that pushed the tag after a merge would
therefore not start a tag-triggered Release workflow.

## Decision

The Release workflow starts on a push to `main` that changes
`lib/hegel/version.rb`. Its first job reads the version and looks for the tag
`v<version>`. When the tag exists, as after a revert to a released version,
the run stops there. Otherwise the publish job waits for the `release`
environment approval, then builds and pushes the gems from the merged
commit. The last job creates the tag on that commit and the GitHub release
together, with `gh release create --target`.

The tag is created last, after the gems are out. A rejected approval then
leaves no tag behind, and rerunning the workflow run releases the same
commit later.

Two alternatives were refused. A workflow that only pushed the tag needs a
personal access token or a GitHub App token to start the tag-triggered
workflow, which is a long-lived secret for one step. Creating the tag before
the approval leaves a tag for a version that may never ship, and the check
job would then skip that version for good.

## Consequences

A release is one merge and one approval. Merge a pull request that changes
the gem version only when that version should ship.

A tag pushed by hand no longer starts a release. The workflow's own run on
`main` is the place to retry one.
