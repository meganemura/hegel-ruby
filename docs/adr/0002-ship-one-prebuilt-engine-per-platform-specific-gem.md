# 0002: Ship one prebuilt engine per platform-specific gem

## Status

Accepted

## Context

hegel-rust publishes libhegel as GitHub release assets. Release v0.32.5
carries ten assets: one shared library and one sha256 checksum, for each of
five platforms (`darwin-arm64`, `linux-amd64`, `linux-arm64`,
`windows-amd64`, `windows-arm64`).

The other implementations distribute these prebuilt libraries in different
shapes. The TypeScript implementation publishes one npm package per
platform, such as `@hegeldev/hegel-linux-x64`, listed as an
`optionalDependencies` entry so npm installs only the matching one. The Go
implementation embeds all five binaries into one module, behind
per-platform `go:embed` build tags. A build for one target links in only
its own binary. The OCaml implementation's loader can also download the
matching binary at install or first run, through a `dune` site that a
release tarball prefills.

RubyGems can build one physical gem per `platform` value declared in a
gemspec. Bundler and RubyGems then install and require the gem matching the
local platform automatically.

## Decision

Publish `hegeltest` as five platform-specific gems, one prebuilt libhegel
bundled in each, following the model the TypeScript implementation's
per-platform npm packages set.

libhegel resolves in two steps: `HEGEL_LIBHEGEL_PATH`, naming a file or a
directory that contains one, checked first; the platform gem's bundled
copy otherwise. The Go, TypeScript, Java, and OCaml implementations all
check `HEGEL_LIBHEGEL_PATH` before falling back to their own bundled or
downloaded engine.

## Consequences

No Intel-Mac gem can ship, since v0.32.5's release assets cover five
platforms and Intel Mac is not one of them. That platform needs
`HEGEL_LIBHEGEL_PATH` and a local build.

Only the resolution step, `HEGEL_LIBHEGEL_PATH` then the bundled copy,
depends on how libhegel reaches the gem. The rest of the library calls
`Hegel::LibHegel` the same way, regardless of where the file came from.
