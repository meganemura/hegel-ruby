# frozen_string_literal: true

module Hegel
  # The libhegel engine release these bindings target. This is independent of
  # Hegel::VERSION (the gem's own release): hegel-go and hegel-typescript keep
  # the two separate too, so bumping the pinned engine can land as its own
  # commit without also releasing a new gem version.
  LIBHEGEL_VERSION = "0.32.5"
end
