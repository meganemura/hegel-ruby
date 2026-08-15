# 0001: Bind libhegel through Fiddle

## Status

Superseded by [ADR 0013](0013-bind-libhegel-through-the-ffi-gem.md),
which binds libhegel through the `ffi` gem instead, on the measurement
[ADR 0008](0008-revisit-the-binding-after-milestone-c-on-measurement.md)
scheduled.

## Context

libhegel is hegel-rust's native engine, exposed as a C ABI in
`hegel-c/include/hegel.h`. It runs in the same process as its caller.
Nearly every function takes a `hegel_context_t*` as its first argument and
returns a `hegel_result_t` status code.

CRuby needs a way to call that ABI. A C extension can call it directly, but
building one needs a compiler at gem install time. Fiddle is a library
bundled with Ruby. It wraps libffi and `dlopen`, so it calls a C function
by address without compiling anything.

The other implementations bind the same ABI under different constraints.
The Java implementation drives it through the Foreign Function and Memory
API. It caches one `MethodHandle` per C symbol, behind a `Libhegel`
interface; `RealLibhegel` implements that interface in production, and a
fake implements it in tests. The Go implementation opens the library with
`dlopen` directly, giving each C symbol a Go func-typed struct field. The
OCaml implementation binds through `ctypes`, declaring each function with
`Foreign.foreign` over a handle from `Dl.dlopen`. The C++ implementation
links the library at compile time and calls its functions directly, with
no runtime loading step.

## Decision

Bind libhegel through Fiddle (`~> 1.1`). Confine every raw Fiddle call to
one module, `Hegel::LibHegel`. The rest of the library will call that
module's wrappers. This matches the way the Java implementation's
`Libhegel` interface sits between its runner and the raw FFI calls.

## Consequences

Installing the gem needs no compiler and no link step against `hegel.h`.
The Go binding shares this property: it opens the library at run time
instead of linking against it.

`Hegel::LibHegel` needs a substitute implementation for testing error-code
translation without a real engine loaded. The Java implementation's fake
binding plays that role in its own test suite.

The gem can use only the Fiddle API that ships in Ruby 3.3's bundled
fiddle, 1.1.2, since that Ruby is the oldest one supported.

Whether `Fiddle::Closure` behaves the same from fiddle 1.1.2 through 1.1.8
has not been checked yet.
