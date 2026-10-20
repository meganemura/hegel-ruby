# 0027: Let each release run wait for its own approval

## Status

Accepted. Removes the `release` concurrency group from the workflow that
[ADR 0024](0024-release-when-a-merge-changes-the-gem-version.md) describes.
The merge trigger and the `release` environment approval stay.

## Context

The Release workflow had the concurrency group `release`, with
`cancel-in-progress: false`. GitHub keeps at most one pending run in a
group. When a newer run queues, GitHub cancels the pending one.

A run that waits for the `release` environment approval is in progress. So
while one version waited for approval, the run of the next merged version
waited behind it, and the run of the version after that cancelled it.
Measured on 2026-10-20 from the Actions runs of the Release workflow:

- The run for 0.3.2 had waited for approval since 2026-10-16.
- The run for 0.3.3 queued on 2026-10-18 and stayed pending behind it.
- When the run for 0.3.4 queued on 2026-10-20, GitHub cancelled the 0.3.3
  run.

A cancelled run leaves no sign in the repository, and the check job of a
later run looks at its own version only. So 0.3.3 would never be released,
unless somebody reran that run by hand.

## Decision

The workflow has no concurrency group. Each merge that changes the version
starts a run that waits for its own approval. Runs for different versions
share no tag and no gem, so they can run side by side.

One alternative was refused: a concurrency group per commit. It allows the
same runs as no group, and adds a setting that a reader must understand.

## Consequences

Each version that is merged gets its own run on the Actions page, waiting
for approval. The maintainer approves each version that should ship, and
rejects each one that should not. Approving an old run publishes that old
version from its own commit.
