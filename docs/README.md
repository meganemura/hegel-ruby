# Documentation

An index of the design records for `hegel-ruby`.

- [architecture.md](architecture.md) — the layers between Ruby and
  libhegel, and the boundary each one draws.

## Architecture Decision Records

- [0001 — Bind libhegel through Fiddle](adr/0001-bind-libhegel-through-fiddle.md)
- [0002 — Ship one prebuilt engine per platform-specific gem](adr/0002-ship-one-prebuilt-engine-per-platform-specific-gem.md)
- [0003 — Publish as hegeltest, require as hegel](adr/0003-publish-as-hegeltest-require-as-hegel.md)
- [0004 — Expose generators through a mixin, with keyword options](adr/0004-expose-generators-through-a-mixin-with-keyword-options.md)
- [0005 — Name drawn values from the caller's source with Prism](adr/0005-name-drawn-values-from-the-callers-source-with-prism.md)
- [0006 — Verify the binding in seven layers, with full coverage](adr/0006-verify-the-binding-in-seven-layers-with-full-coverage.md)

A new decision gets a new record. A changed decision supersedes the old
record instead of editing it, so the history stays readable.
