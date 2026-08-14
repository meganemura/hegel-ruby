# frozen_string_literal: true

module Hegel
  # Wraps one libhegel test-case handle. This is the A3 slice of the engine's
  # draw surface: hegel_generate_integer and hegel_generate_boolean directly,
  # nothing built on top of them yet.
  #
  # This is not a throwaway API. The Generator class planned for a later task
  # (tc.draw(generator)) is built on these same two primitives, the way every
  # other Hegel binding layers its higher-level generators over a small
  # native draw surface.
  class TestCase
    # +impl+ and +ctx+ are carried alongside +handle+ so each draw call can
    # reach the same LibHegel implementation and context the run loop opened,
    # without this class knowing anything about Fiddle or the Fake.
    def initialize(impl, ctx, handle)
      @impl = impl
      @ctx = ctx
      @handle = handle
    end

    # hegel_generate_integer: an integer in [min_value, max_value].
    def draw_integer(min_value, max_value)
      @impl.generate_integer(@ctx, @handle, min_value, max_value)
    end

    # hegel_generate_boolean: true with probability +p+ (default 0.5).
    def draw_boolean(p = 0.5)
      @impl.generate_boolean(@ctx, @handle, p, false, false)
    end
  end
end
