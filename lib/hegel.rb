# frozen_string_literal: true

require_relative "hegel/version"
require_relative "hegel/errors"
require_relative "hegel/runner"
require_relative "hegel/lib_hegel/real"

# Hegel is a property-based testing library for Ruby. It drives libhegel, the
# native engine that also backs the Rust, Go, TypeScript, Java, OCaml, and C++
# implementations of the Hegel protocol.
#
# The gem is named `hegeltest` while the namespace and require path are
# `hegel`, mirroring the Rust implementation: the published crate is
# `hegeltest` and callers write `use hegel::...`.
module Hegel
  module_function

  # Runs +block+ as a Hegel property, drawing test cases from the +tc+ it
  # yields (see Hegel::TestCase). Returns nil on a passing run. On a failing
  # run, re-raises the exception the smallest failing case's body raised,
  # class and backtrace intact, so a host test framework reports it as its
  # own assertion failure rather than as a Hegel-specific one. Raises
  # Hegel::Error for a run-level failure instead of a property failure.
  #
  # +test_cases+, +seed+, +derandomize+, and +verbosity+ all default to nil,
  # which means the same thing for each of them: do not call the matching
  # libhegel setter, and let the engine's own default apply instead. See
  # Hegel::Settings for the keyword-to-setter mapping and the verbosity
  # Symbols it accepts.
  #
  # +impl+ exists for tests: it lets Hegel::LibHegel::Fake stand in for the
  # real engine. Ordinary callers never pass it. Its default expression
  # (#default_impl) only runs when +impl+ is not given, so a test that does
  # pass one never opens the native library at all.
  def test(test_cases: nil, seed: nil, derandomize: nil, verbosity: nil, impl: default_impl, &block)
    Runner.run(impl: impl, test_cases: test_cases, seed: seed, derandomize: derandomize, verbosity: verbosity,
      &block)
  end

  # The Hegel::LibHegel::Real instance #test uses by default, built once and
  # reused: Hegel::LibHegel::Real#initialize opens the native library, and
  # that should not happen again on every #test call in a process that calls
  # it more than once. Building it here rather than at load time also means a
  # caller who always passes their own +impl:+ never opens the library.
  def default_impl
    @default_impl ||= LibHegel::Real.new
  end
end
