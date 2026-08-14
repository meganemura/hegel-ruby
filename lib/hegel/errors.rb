# frozen_string_literal: true

module Hegel
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
end
