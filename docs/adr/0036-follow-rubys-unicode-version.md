# 0036: Follow Ruby's Unicode version

## Status

Accepted.

## Context

libhegel 0.48.0 adds `hegel_set_unicode_version`. It sets, for the whole
process, the Unicode version that the text, regex, and grammar generators
follow: the General Categories an alphabet is built from, and the `\w`,
`\d`, `\s`, word boundaries, and case-insensitive matching of patterns. The
engine has tables for Unicode 14.0.0 to 17.0.0. A binding that never calls it
gets the newest.

Ruby classifies characters by the Unicode version it was built with, which
`RbConfig::CONFIG["UNICODE_VERSION"]` reports: 15.0.0 on Ruby 3.4. With the
engine's 17.0.0 tables, `text(categories: ["Lu"])` can draw a character Ruby
calls unassigned, and `from_regex` can draw a string Ruby's own `Regexp` reads
differently. U+20C1 is one such character: a currency sign in 17.0.0, and
unassigned in every earlier version.

The Python frontend in hegeldev/hegel calls the function at import with
`unicodedata.unidata_version`, for the same reason. The Rust frontend declares
it in `frontends/rust/src/ffi/sys/fns.rs`; a search of `frontends/rust/src` at
the `libhegel/0.48.0` tag finds that declaration as its one occurrence, so this
gem follows the Python frontend here.

## Decision

`LibHegel::Real#initialize` passes `RbConfig::CONFIG["UNICODE_VERSION"]` to
`hegel_set_unicode_version`, next to the engine version check, so that every
generator built afterwards follows Ruby's tables. No keyword exposes it. ADR
0015 leaves mechanism to each binding, and which host's tables the engine
follows is mechanism: the interface stays the same, and a drawn value now
means what Ruby takes it to mean.

A version the engine has no tables for raises `Hegel::Error` when the engine
is loaded. Ruby 3.4, the oldest Ruby this gem supports, reports 15.0.0, and
the engine answers a version newer than its own with its newest tables, so
no supported Ruby reaches that error.

## Consequences

On Ruby 3.4, characters assigned in Unicode 15.1.0 to 17.0.0 are drawn as
unassigned (`Cn`) rather than in their new categories, as Ruby classifies
them.

The setting is process-wide, so a test that changes it puts back Ruby's
version afterwards.
