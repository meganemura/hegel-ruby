# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hegel"

# Use a build already fetched by `rake libhegel:fetch`, if any (a no-op otherwise: ENV#[]= with nil deletes).
ENV["HEGEL_LIBHEGEL_PATH"] ||= Dir[File.expand_path("../tmp/libhegel/*/*.{dylib,so,dll}", __dir__)].max

require "minitest/autorun"
