# frozen_string_literal: true

require_relative "draw_name"
require_relative "lib_hegel"

module Hegel
  # Wraps one libhegel test-case handle: the native draw surface
  # (#generate_integer, #start_span, #new_collection, and so on) every
  # Hegel::Generator#do_draw is built on, plus the two recording entry
  # points a caller (or #draw) reaches for -- #draw_integer/#draw_boolean
  # for the two primitive draws, #draw for a Hegel::Generator.
  #
  # The native methods below intentionally do not record: a Hegel::Generator
  # composing several of them (Hegel::Generators::ArrayGenerator drawing one
  # element per loop iteration, say) must produce exactly one report entry
  # for the whole compound value, not one per native call it happens to
  # make. Only #draw_integer, #draw_boolean, and #draw record, each exactly
  # once for its own single value.
  class TestCase
    # #name_for's fallback when a draw has no better name (see below).
    DEFAULT_DRAW_NAME = "draw"

    # Frames from #name_for's own caller_locations call up to the user's own
    # source line: #record_draw's call to #name_for (1), the public
    # draw_integer/draw_boolean/draw call to #record_draw (2), and the
    # user's own call to that public method (3). The same depth serves
    # #draw as it does #draw_integer/#draw_boolean: #draw calls
    # #record_draw only after Hegel::Generator#do_draw has already
    # returned, so a generator's own frames (and any native calls it made)
    # are off the stack by the time #record_draw runs, leaving the same
    # three frames between #name_for and the user's own call site either
    # way. Verified empirically (see test/hegel/test_runner.rb), not just
    # reasoned about: Ruby's caller_locations counts real stack frames, and
    # a wrong guess here would misname every drawn value, not just fail
    # loudly.
    DRAW_CALLER_DEPTH = 3

    # +impl+ and +ctx+ are carried alongside +handle+ so each draw call can
    # reach the same LibHegel implementation and context the run loop opened,
    # without this class knowing anything about the native binding layer or
    # the Fake.
    #
    # +record+ defaults to false: recording is Hegel::Runner's decision, made
    # only for the one, already-shrunk replay that produces a failure report
    # (see #record_draw for why every other iteration skips it).
    def initialize(impl, ctx, handle, record: false)
      @impl = impl
      @ctx = ctx
      @handle = handle
      @record = record
      @draws = record ? [] : nil
    end

    # The (name, value) pairs recorded so far, or nil when this instance was
    # not built to record. Hegel::Runner reads this once, after the block
    # that owns this test case has run to completion or raised.
    attr_reader :draws

    # hegel_generate_integer: an integer in [min_value, max_value].
    def draw_integer(min_value, max_value, label: nil)
      value = generate_integer(min_value, max_value)
      record_draw(label, value)
      value
    end

    # hegel_generate_boolean: true with probability +p+ (default 0.5).
    def draw_boolean(p = 0.5, label: nil)
      value = generate_boolean(p)
      record_draw(label, value)
      value
    end

    # Draws +generator+ (a Hegel::Generator) and records the single value it
    # produced, however many native calls +generator+ made to produce it.
    # +label+ is threaded through to #record_draw the same way it is for
    # #draw_integer/#draw_boolean, wins over a recovered name the same way.
    def draw(generator, label: nil)
      value = generator.do_draw(self)
      record_draw(label, value)
      value
    end

    # hegel_generate_integer, without recording. Hegel::Generators::
    # IntegerGenerator's own primitive; #draw_integer is this plus
    # recording.
    def generate_integer(min_value, max_value)
      @impl.generate_integer(@ctx, @handle, min_value, max_value)
    end

    # hegel_generate_boolean, without recording. Hegel::Generators::
    # BooleanGenerator's own primitive; #draw_boolean is this plus
    # recording.
    def generate_boolean(p = 0.5)
      @impl.generate_boolean(@ctx, @handle, p, false, false)
    end

    # hegel_generate_float. Hegel::Generators::FloatGenerator's own
    # primitive.
    def generate_float(width, min_value, max_value, allow_nan:, allow_infinity:, exclude_min:, exclude_max:,
      smallest_nonzero_magnitude:)
      @impl.generate_float(@ctx, @handle, width, min_value, max_value, allow_nan, allow_infinity, exclude_min,
        exclude_max, smallest_nonzero_magnitude)
    end

    # hegel_start_span, labelled with one of the Hegel::LibHegel::
    # HEGEL_LABEL_* constants. Every compound Hegel::Generator (map, filter,
    # arrays) opens one of these around its own draw; see #stop_span.
    def start_span(label)
      @impl.start_span(@ctx, @handle, label)
    end

    # hegel_stop_span, closing the span #start_span most recently opened.
    # +discard+ true marks it rejected (a filter predicate that did not
    # hold), so libhegel retries from before the span opened.
    def stop_span(discard: false)
      @impl.stop_span(@ctx, @handle, discard)
    end

    # hegel_new_collection: Hegel::Generators::ArrayGenerator's own sizing
    # primitive, paired with #collection_more and #collection_free.
    def new_collection(min_size, max_size)
      @impl.new_collection(@ctx, @handle, min_size, max_size)
    end

    # hegel_collection_more: whether to draw another element into
    # +collection+.
    def collection_more(collection)
      @impl.collection_more(@ctx, @handle, collection)
    end

    # hegel_collection_reject: tells libhegel the element most recently
    # drawn under +collection+ is invalid (a duplicate key or value, for
    # Hegel::Generators::SetGenerator/HashGenerator), so the next
    # #collection_more call offers another attempt at the same slot instead
    # of treating the collection as one element closer to done.
    def collection_reject(collection, why: nil)
      @impl.collection_reject(@ctx, @handle, collection, why)
    end

    # hegel_collection_free.
    def collection_free(collection)
      @impl.collection_free(@ctx, collection)
    end

    # Runs the block with a text generator handle scoped to this one call,
    # freeing it before returning. See Hegel::Generators::TextGenerator for
    # why this is built fresh per draw rather than cached on the generator
    # instance. Named for what it builds (hegel_string_generator_text), to
    # read the same way as #with_regex_generator/#with_email_generator/
    # #with_url_generator/#with_domain_generator below, each named for its
    # own hegel_string_generator_* call.
    def with_text_generator(**kwargs, &block)
      with_generator_handle(@impl.string_generator_text(@ctx, **kwargs), &block)
    end

    # Runs the block with a regex-matching string generator handle built
    # from +pattern+/+fullmatch+ (see #string_generator_regex), freeing it
    # via #with_generator_handle whether the block returns or raises.
    def with_regex_generator(pattern, fullmatch:, &block)
      with_generator_handle(string_generator_regex(pattern, fullmatch), &block)
    end

    # Runs the block with an email-address string generator handle (see
    # #string_generator_email), freed the same way as #with_regex_generator.
    def with_email_generator(&block)
      with_generator_handle(string_generator_email, &block)
    end

    # Runs the block with a URL string generator handle (see
    # #string_generator_url), freed the same way as #with_regex_generator.
    def with_url_generator(&block)
      with_generator_handle(string_generator_url, &block)
    end

    # Runs the block with a domain-name string generator handle built from
    # +max_length+ (see #string_generator_domain), freed the same way as
    # #with_regex_generator.
    def with_domain_generator(max_length:, &block)
      with_generator_handle(string_generator_domain(max_length), &block)
    end

    # hegel_generate_string against +generator+ (from #with_text_generator,
    # #with_regex_generator, #with_email_generator, #with_url_generator, or
    # #with_domain_generator).
    def generate_string(generator)
      @impl.generate_string(@ctx, @handle, generator)
    end

    # hegel_generate_bytes. A future Hegel::Generators::BinaryGenerator's
    # own primitive, the bytes counterpart to #generate_string.
    def generate_bytes(min_size, max_size)
      @impl.generate_bytes(@ctx, @handle, min_size, max_size)
    end

    # hegel_generate_ipv4, returning the address's 4 raw bytes. Converting
    # to a caller-facing address type (IPAddr or similar) is left to the
    # generator built on top of this call.
    def generate_ipv4
      @impl.generate_ipv4(@ctx, @handle)
    end

    # hegel_generate_ipv6, returning the address's 16 raw bytes. Same
    # division of labor as #generate_ipv4.
    def generate_ipv6
      @impl.generate_ipv6(@ctx, @handle)
    end

    # hegel_string_generator_regex. +alphabet+ is an optional string
    # generator handle (from #with_text_generator), or nil (the default)
    # for the header's documented "no particular alphabet" case. Public,
    # like the three constructors below it, because
    # test/hegel/test_lib_hegel.rb's own layer-1 conformance test already
    # calls all four (and #string_generator_free) directly against the
    # Fake to prove this thin delegation reaches +@impl+ correctly; a
    # Hegel::Generator's do_draw should reach it only through
    # #with_regex_generator instead.
    def string_generator_regex(pattern, fullmatch, alphabet = nil)
      @impl.string_generator_regex(@ctx, pattern, fullmatch, alphabet)
    end

    # hegel_string_generator_email. Public for the same reason
    # #string_generator_regex is; reached only through
    # #with_email_generator otherwise.
    def string_generator_email
      @impl.string_generator_email(@ctx)
    end

    # hegel_string_generator_url. Public for the same reason
    # #string_generator_regex is; reached only through #with_url_generator
    # otherwise.
    def string_generator_url
      @impl.string_generator_url(@ctx)
    end

    # hegel_string_generator_domain. Public for the same reason
    # #string_generator_regex is; reached only through
    # #with_domain_generator otherwise.
    def string_generator_domain(max_length)
      @impl.string_generator_domain(@ctx, max_length)
    end

    # hegel_string_generator_free, for a handle built by
    # #string_generator_regex, #string_generator_email,
    # #string_generator_url, or #string_generator_domain. Public for the
    # same reason #string_generator_regex is: the layer-1 conformance test
    # calls it directly to prove the delegation. #with_generator_handle
    # below is what pairs it with one of the four constructors for a
    # do_draw.
    def string_generator_free(generator)
      @impl.string_generator_free(@ctx, generator)
    end

    private

    # Runs the block with +generator+, freeing it via #string_generator_free
    # whether the block returns or raises. The one #ensure
    # #with_regex_generator/#with_email_generator/#with_url_generator/
    # #with_domain_generator above share, so each of them stays a single
    # line and none writes its own begin/ensure. Private, unlike the four
    # methods that call it: a public version would take an already-built
    # handle as its argument, the same shape a do_draw could otherwise call
    # and forget to free. Keeping it private leaves #with_regex_generator
    # and friends as the sanctioned path into a do_draw, each already
    # pairing its own acquire with this release in one call.
    def with_generator_handle(generator)
      yield generator
    ensure
      string_generator_free(generator)
    end

    # Records (name, value) for the eventual failure report. A no-op unless
    # +record+ was true at #initialize: a run iterates the generation and
    # shrink phases far more than once (Hegel::Runner.drive's own comment
    # measured 1003 iterations for a 20-test-case run that always failed),
    # so recording -- and later #inspect-ing -- every draw there would
    # dominate a failing run's cost. Only the last, already-shrunk replay
    # pays for it.
    def record_draw(label, value)
      return unless @record

      @draws << [name_for(label, DRAW_CALLER_DEPTH), value]
    end

    # The single place a draw's name is decided, tried in this order: the
    # caller's own label:, the name Hegel::DrawName recovers from the
    # caller's own source (see docs/adr/0005), then a generic fallback.
    # +depth+ is how many caller_locations frames separate this call from
    # the user's own source line (see DRAW_CALLER_DEPTH); +location+ is nil
    # only when the stack is shallower than +depth+, which no real draw_*
    # call site produces -- defensive, not a path this binding's own calls
    # reach.
    def name_for(label, depth)
      return label if label

      location = caller_locations(depth, 1)&.first
      (location && DrawName.for(location.path, location.lineno)) || DEFAULT_DRAW_NAME
    end
  end
end
