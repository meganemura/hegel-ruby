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

    # hegel_phase_t, named from hegel.h's enum of the same name. A bitwise
    # OR of these is passed to hegel_settings_set_phases; the default is
    # HEGEL_PHASE_ALL.
    HEGEL_PHASE_EXPLICIT = 1
    HEGEL_PHASE_REUSE = 2
    HEGEL_PHASE_GENERATE = 4
    HEGEL_PHASE_TARGET = 8
    HEGEL_PHASE_SHRINK = 16
    HEGEL_PHASE_ALL = 31

    # hegel_health_check_t, named from hegel.h's enum of the same name. A
    # bitwise OR of these is passed to
    # hegel_settings_set_suppress_health_check; the default is all
    # enabled.
    HEGEL_HC_FILTER_TOO_MUCH = 1
    HEGEL_HC_TOO_SLOW = 2
    HEGEL_HC_TEST_CASES_TOO_LARGE = 4
    HEGEL_HC_LARGE_INITIAL_TEST_CASE = 8

    # hegel_label_t, named from hegel.h's enum of the same name. Passed to
    # hegel_start_span to identify what kind of structure a span groups.
    # Copied through HEGEL_LABEL_SET_CHOICE (value 33). The header
    # describes the last two, HEGEL_LABEL_FRESH_ID and
    # HEGEL_LABEL_SET_CHOICE, as spans the engine opens itself around a
    # hegel_pool_add / hegel_pool_generate call; a caller never passes
    # either to hegel_start_span.
    #
    # The header documents that "Libraries may use any stable u64 to
    # define their own spans" — so a caller building its own compound
    # generator on top of this boundary can pick any u64 that does not
    # collide with the reserved values below.
    HEGEL_LABEL_LIST = 1
    HEGEL_LABEL_LIST_ELEMENT = 2
    HEGEL_LABEL_SET = 3
    HEGEL_LABEL_SET_ELEMENT = 4
    HEGEL_LABEL_MAP = 5
    HEGEL_LABEL_MAP_ENTRY = 6
    HEGEL_LABEL_TUPLE = 7
    HEGEL_LABEL_ONE_OF = 8
    HEGEL_LABEL_OPTIONAL = 9
    HEGEL_LABEL_FIXED_DICT = 10
    HEGEL_LABEL_FLAT_MAP = 11
    HEGEL_LABEL_FILTER = 12
    HEGEL_LABEL_MAPPED = 13
    HEGEL_LABEL_SAMPLED_FROM = 14
    HEGEL_LABEL_ENUM_VARIANT = 15
    HEGEL_LABEL_FEATURE_FLAG = 16
    HEGEL_LABEL_REGEX = 17
    HEGEL_LABEL_EMAIL = 18
    HEGEL_LABEL_URL = 19
    HEGEL_LABEL_DOMAIN = 20
    HEGEL_LABEL_DATE = 21
    HEGEL_LABEL_TIME = 22
    HEGEL_LABEL_DATETIME = 23
    HEGEL_LABEL_UUID = 24
    HEGEL_LABEL_IP_ADDRESS = 25
    HEGEL_LABEL_INTEGER = 26
    HEGEL_LABEL_FLOAT = 27
    HEGEL_LABEL_BOOLEAN = 28
    HEGEL_LABEL_BYTES = 29
    HEGEL_LABEL_STRING = 30
    HEGEL_LABEL_STATEFUL_RULE = 31
    HEGEL_LABEL_FRESH_ID = 32
    HEGEL_LABEL_SET_CHOICE = 33

    # HEGEL_STATE_MACHINE_DONE, named from hegel.h's #define of the same
    # name. hegel_state_machine_next_rule writes this to its
    # out_rule_index parameter once the current test case's step budget
    # is exhausted; see LibHegel::Real#state_machine_next_rule for why
    # that raw sentinel is returned rather than translated to nil.
    HEGEL_STATE_MACHINE_DONE = -1

    # hegel_new_collection's max_size accepts UINT64_MAX to mean "no upper
    # bound", in the header's own words. Ruby has no fixed-width integer
    # type to read that constant off, so it is spelled out here as the
    # value a 64-bit unsigned integer maxes out at.
    HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED = (2**64) - 1

    # hegel_generate_float's smallest_nonzero_magnitude must be positive
    # and finite. The header names 5e-324 as the width-64 value that
    # places no restriction on which nonzero magnitudes get drawn.
    HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED = 5e-324

    # The methods every implementation of this boundary (Real, Fake) must
    # answer to. Held as data, not a Ruby interface/protocol, because Ruby
    # has none; test/hegel/test_lib_hegel.rb asserts every implementation
    # responds to each name here.
    METHODS = %i[
      context_new context_free context_last_error version
      settings_new settings_free settings_set_test_cases settings_set_verbosity
      settings_set_seed settings_set_derandomize settings_set_database
      run_start next_test_case run_free test_case_free mark_complete
      generate_boolean generate_integer generate_integer_big
      run_result run_result_free run_result_status run_result_error
      run_result_failure_count run_result_failure failure_free failure_origin
      failure_reproduction_blob test_case_from_blob
      start_span stop_span
      new_collection collection_more collection_reject collection_free
      generate_float
      string_generator_text string_generator_free generate_string generate_string_result_free
      generate_bytes generate_bytes_result_free
      string_generator_regex string_generator_email string_generator_url string_generator_domain
      generate_ipv4 generate_ipv6 generate_uuid
      generate_date generate_time generate_datetime
      settings_set_phases settings_set_suppress_health_check settings_set_report_multiple_failures
      settings_set_database_key settings_set_stateful_step_count
      target
      new_pool pool_add pool_generate pool_free
      new_state_machine state_machine_next_rule state_machine_rule_rejected state_machine_free
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

    # hegel_generate_integer_big's own documented convention for
    # min_value/max_value/out_value: two's-complement little-endian signed
    # byte buffers. Pure Ruby arithmetic, no native marshalling, so this is
    # unit-testable directly (test/hegel/test_lib_hegel.rb round-trips it)
    # and shared unchanged between LibHegel::Real's bounds-encode and
    # result-decode, kept out of real.rb so that direct testing stays
    # possible.
    #
    # +n+'s minimal two's-complement byte length is n.bit_length / 8 + 1.
    # Integer#bit_length reports one bit fewer at a negative power of two
    # (-128 is 7 bits, 128 is 8), so this formula needs no separate
    # sign-bit adjustment there; verified against a brute-force
    # minimal-length search over both signs and the int32/int64/2**100
    # boundaries.
    def encode_integer_le(n)
      byte_length = (n.bit_length / 8) + 1
      byte_length.times.map { |i| (n >> (8 * i)) & 0xFF }.pack("C*")
    end

    # The inverse of .encode_integer_le. +bytes+ may be longer than the
    # value's own minimal encoding -- the header documents hegel_generate_
    # integer_big's out_value as sign-filled past that length, so a caller
    # may decode the whole out_value_cap-sized buffer and still get the
    # right answer -- so length here is read from +bytes+ itself, not
    # assumed minimal.
    def decode_integer_le(bytes)
      length = bytes.bytesize
      unsigned = bytes.each_byte.with_index.sum { |byte, i| byte << (8 * i) }
      negative = (bytes.getbyte(length - 1) & 0x80) != 0
      negative ? unsigned - (1 << (8 * length)) : unsigned
    end
  end
end
