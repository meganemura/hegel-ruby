# frozen_string_literal: true

require_relative "errors"
require_relative "locate"
require_relative "libhegel_version"

module Hegel
  # The libhegel binding boundary: the small set of methods a connection to
  # the native engine must answer to, plus the result-code translation and
  # context lifecycle shared by every implementation.
  #
  # Ruby has no interface construct, so this module carries the contract two
  # ways: METHODS names every method an implementation must answer to, and
  # a conformance test (test/hegel/test_lib_hegel.rb) asserts that every
  # implementation responds to all of them. LibHegel::Real drives the C ABI;
  # test/support/fake_lib_hegel.rb (not shipped in the gem) is a second,
  # configurable implementation, so the logic built on top of this boundary
  # is testable without the native engine — the same split hegel-java makes
  # between its Libhegel interface, RealLibhegel, and FakeLibhegel.
  module LibHegel
    # hegel_result_t, named from hegel-c/include/hegel.h's enum of the same
    # name. HEGEL_OK is success; every other value is a negative error code.
    HEGEL_OK = 0
    HEGEL_E_STOP_TEST = -1
    HEGEL_E_ASSUME = -2
    HEGEL_E_BACKEND = -3
    HEGEL_E_INVALID_HANDLE = -4
    HEGEL_E_INVALID_ARG = -5
    HEGEL_E_ALREADY_COMPLETE = -6
    HEGEL_E_NOT_COMPLETE = -7
    HEGEL_E_INTERNAL = -8
    HEGEL_E_CONCURRENT_USE = -9

    # The hegel.h name for each code above, so a translated error message
    # names the code instead of leaving the reader to cross-reference the
    # header by number alone.
    CODE_NAMES = {
      HEGEL_OK => "HEGEL_OK",
      HEGEL_E_STOP_TEST => "HEGEL_E_STOP_TEST",
      HEGEL_E_ASSUME => "HEGEL_E_ASSUME",
      HEGEL_E_BACKEND => "HEGEL_E_BACKEND",
      HEGEL_E_INVALID_HANDLE => "HEGEL_E_INVALID_HANDLE",
      HEGEL_E_INVALID_ARG => "HEGEL_E_INVALID_ARG",
      HEGEL_E_ALREADY_COMPLETE => "HEGEL_E_ALREADY_COMPLETE",
      HEGEL_E_NOT_COMPLETE => "HEGEL_E_NOT_COMPLETE",
      HEGEL_E_INTERNAL => "HEGEL_E_INTERNAL",
      HEGEL_E_CONCURRENT_USE => "HEGEL_E_CONCURRENT_USE"
    }.freeze

    # hegel_status_t, named from hegel.h's enum of the same name. Passed to
    # hegel_mark_complete to describe how a test case ended.
    HEGEL_STATUS_VALID = 0
    HEGEL_STATUS_INVALID = 1
    HEGEL_STATUS_OVERRUN = 2
    HEGEL_STATUS_INTERESTING = 3

    # hegel_run_status_t, named from hegel.h's enum of the same name. Read
    # via hegel_run_result_status once a run has finished.
    HEGEL_RUN_STATUS_PASSED = 0
    HEGEL_RUN_STATUS_FAILED = 1
    HEGEL_RUN_STATUS_ERROR = 2

    # hegel_verbosity_t, named from hegel.h's enum of the same name. Passed
    # to hegel_settings_set_verbosity.
    HEGEL_VERBOSITY_QUIET = 0
    HEGEL_VERBOSITY_NORMAL = 1
    HEGEL_VERBOSITY_VERBOSE = 2
    HEGEL_VERBOSITY_DEBUG = 3

    # The methods every implementation of this boundary (Real, Fake) must
    # answer to. Held as data, not a Ruby interface/protocol, because Ruby
    # has none; test/hegel/test_lib_hegel.rb asserts every implementation
    # responds to each name here.
    METHODS = %i[
      context_new context_free context_last_error version
      settings_new settings_free settings_set_test_cases settings_set_verbosity
      settings_set_seed settings_set_derandomize settings_set_database
      run_start next_test_case run_free test_case_free mark_complete
      generate_boolean generate_integer
      run_result run_result_free run_result_status run_result_error
      run_result_failure_count run_result_failure failure_free failure_origin
      failure_reproduction_blob test_case_from_blob
    ].freeze

    module_function

    # Runs the block with a context obtained from +impl.context_new+,
    # freeing it via +impl.context_free+ whether the block returns or
    # raises.
    #
    # A block is the only construct used here: hegel_context_free requires
    # every other handle taking this context to be freed first, so the
    # context must outlive them all, and Ruby's GC gives finalizers no
    # ordering guarantee to rely on instead. The block's caller is the
    # context's owner and holds it for exactly as long as the block runs.
    def with_context(impl)
      ctx = impl.context_new
      yield ctx
    ensure
      impl.context_free(ctx)
    end

    # Raises the exception +code+ translates to, or returns without effect
    # for HEGEL_OK. The message is read from +impl.context_last_error(ctx)+
    # immediately, since libhegel's own buffer for it is invalidated by the
    # next call taking the same context — by the time a caller further up
    # the stack could read it, it might already describe a different call.
    def check!(impl, ctx, code)
      return if code == HEGEL_OK

      # An engine newer than the pinned one can return a code these bindings
      # have no name for, which is the situation the version warning exists
      # to announce. Naming it plainly beats failing to look it up, because a
      # KeyError here would replace the engine's own diagnostic with a
      # message about a missing hash key.
      name = CODE_NAMES[code] || "unknown result code"
      message = "#{name} (#{code}): #{impl.context_last_error(ctx)}"
      case code
      when HEGEL_E_STOP_TEST then raise StopTest, message
      when HEGEL_E_ASSUME then raise AssumeFailed, message
      else raise Hegel::Error, message
      end
    end

    # Warns on +io+ when +impl.version(ctx)+ differs from the engine
    # version these bindings were built for (Hegel::LIBHEGEL_VERSION), and
    # does nothing when they match. Never raises: a mismatched engine is
    # still usable, only untested against, so this is a warning rather than
    # a load failure. +io+ defaults to $stderr and is overridable so a
    # caller (and a test) can capture the warning instead.
    def warn_on_version_mismatch(impl, ctx, io: $stderr)
      loaded = impl.version(ctx)
      return if loaded == Hegel::LIBHEGEL_VERSION

      io.puts(<<~MESSAGE.chomp)
        hegel: loaded libhegel #{loaded} but these bindings were built for #{Hegel::LIBHEGEL_VERSION}; behaviour may differ. Unset HEGEL_LIBHEGEL_PATH to use the bundled engine, or point it at a matching build.
      MESSAGE
    end
  end
end
