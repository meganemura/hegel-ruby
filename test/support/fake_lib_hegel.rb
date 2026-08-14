# frozen_string_literal: true

require "hegel/lib_hegel"

module Hegel
  module LibHegel
    # A configurable stand-in for LibHegel::Real, so logic built on top of
    # this boundary is testable without opening the native engine. This
    # file lives under test/support/, and hegeltest.gemspec's file list
    # drops everything under test/, so it never ships in the gem.
    #
    # Every value an implementation hands back (the version string, the
    # context's last-error message, and the result code #version reports)
    # is a plain accessor here, so a test can set exactly the condition it
    # wants to exercise — most usefully, an error code that drives
    # LibHegel.check! down a path the real engine would rarely take.
    class Fake
      # Writers only: #version is also the name of the instance method
      # below that mimics the real ABI call, so an attr_accessor's 0-arity
      # reader would collide with (and be overwritten by) that method
      # definition. Nothing here needs to read a value back once set.
      attr_writer :version, :version_code, :last_error
      attr_reader :freed_contexts

      def initialize
        @version = Hegel::LIBHEGEL_VERSION
        @version_code = HEGEL_OK
        @last_error = "fake error"
        @freed_contexts = []
      end

      # A fresh, distinct handle per call; the only thing callers may do
      # with it is pass it back into another method on this instance.
      def context_new
        Object.new
      end

      # Records +ctx+ (including nil, matching libhegel's own no-op-on-NULL
      # contract) so a test can assert a context was released.
      def context_free(ctx)
        @freed_contexts << ctx
        nil
      end

      def context_last_error(_ctx)
        @last_error
      end

      # Returns #version, or raises the exception LibHegel.check!
      # translates #version_code to.
      def version(ctx)
        LibHegel.check!(self, ctx, @version_code)
        @version
      end
    end
  end
end
