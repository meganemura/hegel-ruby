# frozen_string_literal: true

require "fiddle"
require_relative "../lib_hegel"

module Hegel
  module LibHegel
    # Drives libhegel's C ABI over Fiddle. Every other file works against
    # the plain Ruby values and method calls this class exposes, so a
    # future change to how the native call happens has exactly one file to
    # change.
    #
    # Opens the library and binds all four functions once, in #initialize,
    # and holds them for the instance's lifetime; each call below reuses
    # the already-bound function rather than re-resolving the symbol.
    class Real
      # Opens +path+ (default: Hegel::Locate.resolve) and binds the four
      # functions this boundary calls. Immediately after, opens a context
      # of its own to compare the loaded engine's version against
      # Hegel::LIBHEGEL_VERSION, warning on +io+ (default $stderr) on a
      # mismatch; see LibHegel.warn_on_version_mismatch. +io+ exists so a
      # test can capture the warning instead of writing to the real stderr.
      def initialize(path = Hegel::Locate.resolve, io: $stderr)
        @handle = Fiddle.dlopen(path)

        @context_new_fn = bind("hegel_context_new", [], Fiddle::TYPE_VOIDP)
        @context_free_fn = bind("hegel_context_free", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @context_last_error_fn = bind("hegel_context_last_error", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
        @version_fn = bind("hegel_version", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

        LibHegel.with_context(self) { |ctx| LibHegel.warn_on_version_mismatch(self, ctx, io: io) }
      end

      # hegel_context_new never returns NULL (guaranteed by the header), so
      # the handle returned here is always live.
      def context_new
        @context_new_fn.call
      end

      # No-op when +ctx+ is nil: libhegel documents hegel_context_free as a
      # no-op on NULL, and a Ruby nil marshals to a NULL pointer for a
      # void* argument here, so no separate nil check is needed on this
      # side. The result code is not translated: the header documents this
      # call as always returning HEGEL_OK, so there is nothing to raise.
      def context_free(ctx)
        @context_free_fn.call(ctx)
        nil
      end

      # Copies the message out of libhegel's own buffer into a Ruby String
      # before returning, since the header documents that buffer as
      # borrowed and invalidated by the next call taking the same context.
      def context_last_error(ctx)
        @context_last_error_fn.call(ctx).to_s
      end

      # Returns the loaded engine's version string, or raises the
      # exception LibHegel.check! translates this call's result code to.
      def version(ctx)
        out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = @version_fn.call(ctx, out)
        LibHegel.check!(self, ctx, code)
        out.ptr.to_s
      end

      private

      def bind(symbol, arg_types, ret_type)
        Fiddle::Function.new(@handle[symbol], arg_types, ret_type)
      end
    end
  end
end
