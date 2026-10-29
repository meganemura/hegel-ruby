# 0037: Send a maximum at the engine's default sentinel as no bound

## Status

Accepted.

## Context

libhegel 0.49.0 adds `HEGEL_MAX_SIZE_DEFAULT`, which is `UINT64_MAX - 1`.
`hegel_new_collection`, `hegel_string_generator_text`, and
`hegel_generate_bytes` read that `max_size` as "the caller gave no maximum",
and apply the default of text and bytes: 100, or `min_size + 100` when
`min_size` is above 100. `UINT64_MAX` continues to mean no upper bound. The
engine changelog tells a frontend to pass `UINT64_MAX` for a user's explicit
maximum at or above `HEGEL_MAX_SIZE_DEFAULT`.

Before this change, the gem sent a caller's `max_size` to the engine as
it is. Measured on linux-amd64 with Ruby 3.4.10 against 0.49.0, without this
change, 300 cases of `binary(min_size: 200, max_size: 2**64 - 2)` had 200 to
300 bytes: the engine applied `min_size + 100`. With this change, the same
draw had 200 to 1465 bytes. A Ruby `Integer` has no upper limit, so a caller
can also write a maximum above `UINT64_MAX`. Without this change,
`binary(max_size: 2**70)` raised `RangeError` from the `ffi` gem (measured on
the same setup).

The Rust frontend declares the constant in
`frontends/rust/src/ffi/sys/types.rs` at the `libhegel/0.49.0` tag. Its text
generator, in `frontends/rust/src/generators/strings.rs`, continues to pass
its own default of 100 (inferred from reading that file).

## Decision

`Hegel::LibHegel.max_size_arg` changes a `max_size` at or above
`HEGEL_MAX_SIZE_DEFAULT` to `UINT64_MAX`. `Hegel::TestCase#new_collection`,
`#with_text_generator`, and `#generate_bytes` apply it, so every generator
that sizes a draw through the engine sends the caller's maximum this way.

The gem continues to compute its own default maximum of text and bytes
(`Hegel::Generators.default_max_size`) and to send it as a number. It does not
send the sentinel. The default is the same number, and a reader of the
generator then sees the default in Ruby.

## Consequences

A maximum at or above `2**64 - 2` means no upper bound. No allocation can
reach a size of that order, so a caller who writes one gets the meaning
they wrote. A maximum above `2**64 - 1` also means no upper bound now, where it
raised `RangeError` before.
