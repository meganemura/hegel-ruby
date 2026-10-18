# 0025: Copy each string input into a hegel_string_t

## Status

Accepted.

## Context

libhegel 0.46.0 changed every string in its C interface to a
`hegel_string_t`, a struct of a data pointer and a byte length. An ordinary
input goes by value. An optional input goes through a pointer to the
struct, and a NULL pointer means that the value is absent. An output is a
struct that the engine writes. Before 0.46, a string input was a
NUL-terminated `const char *`, which the `ffi` gem marshals from a Ruby
String with the `:string` type. That type stops at the first NUL, and
`ffi` 1.17.4 raises `ArgumentError` for a String with an interior NUL.

The struct is 16 bytes on a 64-bit platform. The calling conventions do not
pass a struct of that size in the same way: x86-64 System V and AArch64
pass it in two registers, and Windows x64 passes it through a hidden
pointer. This is inferred from the ABI documents of each platform, not
measured here; the CI runs the suite on each of them. A binding that
declared two scalar arguments in place of the struct would match some of
these conventions and not others.

hegel-rust's own frontend (`src/ffi.rs` at `libhegel-v0.47.1`) borrows the
bytes of a Rust string for the length of the call.

## Decision

`LibHegel::Real` declares each `hegel_string_t` argument as
`StringStruct.by_value`, and lets libffi apply the calling convention of the
platform. It declares each optional string argument as `:pointer`, and
passes `nil` for an absent value and a `StringStruct` for a present one, so
that `""` stays different from `nil`. `settings_set_database` needs that
difference: `""` turns the database off, and `nil` keeps the engine's
default directory.

Each input string is copied into a native buffer that the struct holds. The
binding does not point the struct at the memory of the Ruby String: a copy
does not depend on how long the garbage collector keeps that memory in
place (inferred: compaction can move the contents of a short String).
Measured on `ffi` 1.17.4, a struct field keeps the buffer it holds alive
through a full garbage collection. The struct is an argument of the native
call, so the buffer lives until the call returns.

An output is read by its length, not up to its trailing NUL, because an
engine string can hold an interior NUL.

## Consequences

A string that holds a NUL character, for example a `target` label, reaches
the engine whole. Before, it raised `ArgumentError`.

Each string input costs one native allocation and one copy. The strings that
cross on each test case are short: an origin for an interesting case, and
a label for each `target` call.

The rename of `hegel_generate_string_result_free` to
`hegel_owned_string_free` renames the binding method to `owned_string_free`.
`LibHegel::METHODS`, the Fake, and `sig/hegel.rbs` follow it.
