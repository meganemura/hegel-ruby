# frozen_string_literal: true

module Hegel
  # Raised for errors this library detects: a libhegel call that fails, a
  # generator built with arguments the engine rejects, a missing native
  # library. Control flow inside a running test case does not use this class;
  # the control exceptions below descend from Exception instead, so that a
  # `rescue => e` in a test body cannot swallow them.
  #
  # It lives here rather than in hegel.rb so that a file needing only the
  # exception vocabulary can require this one file. Reaching it through
  # hegel.rb would make every such file depend on the whole library, and
  # hegel.rb requires the library back, which is a load-order cycle.
  class Error < StandardError; end

  # standard:disable Lint/InheritException

  # Raised for HEGEL_E_STOP_TEST (-1): libhegel has exhausted its choice
  # budget for the running test case and the caller must abort the test
  # body immediately.
  #
  # Descends from Exception, not StandardError, so that a `rescue => e` (or
  # a bare `rescue`) written in a user's test body cannot catch it. Only the
  # code driving the test case is meant to catch this; letting a test body
  # swallow it would turn "stop now" into "keep going".
  class StopTest < Exception; end

  # Raised for HEGEL_E_ASSUME (-2): an `assume` / `reject` precondition
  # failed, so the current test case is invalid and must be discarded.
  #
  # Descends from Exception for the same reason as StopTest above.
  class AssumeFailed < Exception; end

  # standard:enable Lint/InheritException

  # Say the process is ending, not that a property failed. Every
  # `rescue Exception` in this library re-raises one of these before doing
  # anything else: catching one as a counterexample would have the engine
  # spend its shrink budget minimising an interrupt instead of letting the
  # process exit, and NoMemoryError in particular must not be answered with
  # another native call.
  #
  # Here rather than beside the run loop because two files now rescue
  # Exception -- Hegel::Runner and Hegel::Stateful -- and this is the
  # exception vocabulary both of them need, which is what this file is for.
  FATAL_EXCEPTIONS = [Interrupt, SignalException, SystemExit, NoMemoryError].freeze
end
