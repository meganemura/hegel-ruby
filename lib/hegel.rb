# frozen_string_literal: true

require_relative "hegel/version"

# Hegel is a property-based testing library for Ruby. It drives libhegel, the
# native engine that also backs the Rust, Go, TypeScript, Java, OCaml, and C++
# implementations of the Hegel protocol.
#
# The gem is named `hegeltest` while the namespace and require path are
# `hegel`, mirroring the Rust implementation: the published crate is
# `hegeltest` and callers write `use hegel::...`.
module Hegel
  # Raised for errors this library detects: a libhegel call that fails, a
  # generator built with arguments the engine rejects, a missing native
  # library. Control flow inside a running test case does not use this class;
  # the control exceptions descend from Exception instead, so that a
  # `rescue => e` in a test body cannot swallow them.
  class Error < StandardError; end
end
