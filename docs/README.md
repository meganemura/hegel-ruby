# Documentation

An index of the design records for `hegel-ruby`.

- [architecture.md](architecture.md): the layers between Ruby and
  libhegel, and the boundary each one draws.

## Architecture Decision Records

- [0001: Bind libhegel through Fiddle](adr/0001-bind-libhegel-through-fiddle.md)
- [0002: Ship one prebuilt engine per platform-specific gem](adr/0002-ship-one-prebuilt-engine-per-platform-specific-gem.md)
- [0003: Publish as hegeltest, require as hegel](adr/0003-publish-as-hegeltest-require-as-hegel.md)
- [0004: Expose generators through a mixin, with keyword options](adr/0004-expose-generators-through-a-mixin-with-keyword-options.md)
- [0005: Name drawn values from the caller's source with Prism](adr/0005-name-drawn-values-from-the-callers-source-with-prism.md)
- [0006: Verify the binding in seven layers, with full coverage](adr/0006-verify-the-binding-in-seven-layers-with-full-coverage.md)
- [0007: Ship a thin Ruby skill, shaped for donation](adr/0007-ship-a-thin-ruby-skill-shaped-for-donation.md)
- [0008: Revisit the binding after milestone C, on measurement](adr/0008-revisit-the-binding-after-milestone-c-on-measurement.md)
- [0009: Turn the example database on with a key](adr/0009-turn-the-example-database-on-with-a-key.md)
- [0010: Declare stateful rules with a class macro](adr/0010-declare-stateful-rules-with-a-class-macro.md)
- [0011: Let the test case own every pool drawn from it](adr/0011-let-the-test-case-own-every-pool-drawn-from-it.md)
- [0012: Build a failure origin from the caller's own frame](adr/0012-build-a-failure-origin-from-the-callers-own-frame.md)
- [0013: Bind libhegel through the ffi gem](adr/0013-bind-libhegel-through-the-ffi-gem.md)
- [0014: Name a drawn value only when the draw is the whole assigned value](adr/0014-name-a-drawn-value-only-when-the-draw-is-the-whole-assigned-value.md)
- [0015: Follow the hegeldev interface, and take changes upstream first](adr/0015-follow-the-hegeldev-interface-and-take-changes-upstream-first.md)
- [0016: Run mutation testing with mutineer](adr/0016-run-mutation-testing-with-mutineer.md)
- [0017: Raise the Ruby floor to 3.4](adr/0017-raise-the-ruby-floor-to-3-4.md)
- [0018: Gate mutation testing on a committed baseline](adr/0018-gate-mutation-testing-on-a-committed-baseline.md)
- [0019: Report failures from the cases the engine stamps](adr/0019-report-failures-from-the-cases-the-engine-stamps.md)
- [0020: Derive span labels from generator names](adr/0020-derive-span-labels-from-generator-names.md)
- [0021: Run a state machine in rounds, with its own step count](adr/0021-run-a-state-machine-in-rounds-with-its-own-step-count.md)
- [0022: Keep microsecond times over a nanosecond engine](adr/0022-keep-microsecond-times-over-a-nanosecond-engine.md)
- [0023: Leave unset settings to the engine's profile](adr/0023-leave-unset-settings-to-the-engines-profile.md)
- [0024: Release when a merge changes the gem version](adr/0024-release-when-a-merge-changes-the-gem-version.md)

A new decision gets a new record. A changed decision supersedes the old
record instead of editing it, so the history stays readable.
