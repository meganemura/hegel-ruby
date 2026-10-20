# 0026: Select the engine release repository by version

## Status

Accepted.

## Context

Up to libhegel 0.47.1, hegeldev/hegel-rust published each engine release
with the tag `libhegel-v<version>`. From 0.47.2, the engine and the Rust
frontend live in the monorepo hegeldev/hegel, which publishes each engine
release with the tag `libhegel/<version>`. hegeldev/hegel-rust is now an
archive and gets no new release. The asset names did not change: `hegel.h`,
`libhegel-<os>-<arch>.<ext>`, and `<asset>.sha256`.

Measured on 2026-10-19 with HTTP requests to the release download URLs:
hegeldev/hegel does not carry the assets of the old releases
(`libhegel/0.47.1/hegel.h` gives HTTP 404). Measured on 2026-10-20: each of
the five platform assets of 0.47.2, and its `.sha256` file, gives HTTP 200
from hegeldev/hegel.

## Decision

`Hegel::LibhegelFetch.release_base` selects the repository from the version.
A version of 0.47.2 or later downloads from
`https://github.com/hegeldev/hegel/releases/download/libhegel/<version>`. An
earlier version downloads from
`https://github.com/hegeldev/hegel-rust/releases/download/libhegel-v<version>`.

The rule keeps the old releases reachable. A contributor who checks out an
old commit of this gem can still run `rake libhegel:fetch` for the version
that commit pins.

One alternative was refused: a single base URL for the new repository. It
is shorter, but it breaks `rake libhegel:fetch` on every old commit, because
the new repository does not carry the old assets.

## Consequences

The CHANGELOG rule in CLAUDE.md links the engine release notes and
`libhegel/CHANGELOG.md` in hegeldev/hegel for an engine move to 0.47.2 or
later. The reference paths in CLAUDE.md and `docs/architecture.md` point into
the monorepo tree: `libhegel/` for the engine, and `frontends/rust/` for the
Rust frontend.

If the old releases move to hegeldev/hegel later, the legacy branch can go,
and this record gets a successor.
