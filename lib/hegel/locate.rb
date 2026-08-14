# frozen_string_literal: true

require "rbconfig"
require_relative "../hegel"

module Hegel
  # Resolves the path to the native libhegel shared library.
  #
  # Resolution order:
  #
  # 1. +HEGEL_LIBHEGEL_PATH+ — an explicit override, given as a file path or
  #    a directory that contains the library. This is checked first because
  #    hegel-go, hegel-typescript, hegel-java, and hegel-ocaml all give this
  #    same variable name priority over their own fallback.
  # 2. The copy bundled into the gem under +lib/hegel/libhegel/+.
  #
  # A sibling `../hegel-rust` checkout is deliberately not searched. The env
  # override already covers local-engine-build workflows without depending
  # on any particular checkout layout, and `rake libhegel:fetch` covers the
  # rest; a rule that depends on a layout this repo's own checkout does not
  # have would be an untested, unreachable branch under 100% coverage.
  #
  # Resolution knowledge is confined to this file — every other file calls
  # only Locate.resolve — so a future change to the distribution method
  # (bundled copy vs. runtime download) has one place to change. This module
  # never touches the network; only the development-only `libhegel:fetch`
  # rake task downloads anything.
  module Locate
    # Env var that overrides resolution with an explicit path.
    LIBRARY_PATH_ENV = "HEGEL_LIBHEGEL_PATH"

    # Published release asset name for each supported "<host_cpu>-<host_os>"
    # pair, mirroring the artifacts hegel-rust publishes for the pinned
    # LIBHEGEL_VERSION. Hosts absent from this table (e.g. x86_64-darwin,
    # Intel Mac) are unsupported because hegel-rust does not publish a build
    # for them.
    ASSET_NAMES = {
      "arm64-darwin" => "libhegel-darwin-arm64.dylib",
      "x86_64-linux" => "libhegel-linux-amd64.so",
      "aarch64-linux" => "libhegel-linux-arm64.so",
      "x64-mingw-ucrt" => "libhegel-windows-amd64.dll",
      "aarch64-mingw-ucrt" => "libhegel-windows-arm64.dll"
    }.freeze

    # Directory inside the gem where a platform build may be bundled.
    GEM_LIBHEGEL_DIR = File.expand_path("libhegel", __dir__)

    # Default lookup for the gem-bundled step: the asset file directly under
    # +dir+, or nil if it is not there.
    DEFAULT_FINDER = lambda do |dir, asset|
      path = File.join(dir, asset)
      File.file?(path) ? path : nil
    end

    module_function

    # Resolves a usable libhegel path. Env, host, the gem-bundled directory,
    # and the gem-bundled finder are all injectable so this is testable
    # without a real native library or a real host match.
    #
    # Raises Hegel::Error if the host is unsupported, or if it is supported
    # but no bundled library is found for it.
    def resolve(env: ENV, host_cpu: RbConfig::CONFIG["host_cpu"], host_os: RbConfig::CONFIG["host_os"],
      gem_dir: GEM_LIBHEGEL_DIR, finder: DEFAULT_FINDER)
      overridden = from_env(env, host_os)
      return overridden unless overridden.nil?

      # Host support is checked before any filesystem lookup, so an
      # unsupported host reports itself as unsupported rather than as a
      # confusing "file not found" once the gem-bundled directory is missing
      # or empty.
      asset = asset_name(host_cpu: host_cpu, host_os: host_os)
      finder.call(gem_dir, asset) || raise(Hegel::Error, missing_bundle_message(asset, gem_dir))
    end

    # The release asset name for the given host, or raises Hegel::Error if
    # hegel-rust does not publish a build for it.
    def asset_name(host_cpu:, host_os:)
      ASSET_NAMES.fetch(host_id(host_cpu, host_os)) do
        raise Hegel::Error, unsupported_host_message(host_cpu, host_os)
      end
    end

    # Step 1: the explicit override, or nil if unset or empty. An empty
    # value is treated as unset (not as "use the current directory"), so
    # exporting the variable empty in CI does not silently break resolution.
    def from_env(env, host_os)
      value = env[LIBRARY_PATH_ENV]
      return nil if value.nil? || value.empty?

      File.directory?(value) ? File.join(value, "libhegel.#{ext_of_os(host_os)}") : value
    end

    # "<host_cpu>-<host_os>", normalized to the form ASSET_NAMES keys on.
    def host_id(host_cpu, host_os)
      os = normalize_os(host_os)
      "#{normalize_cpu(host_cpu, os)}-#{os}"
    end

    # RbConfig::CONFIG["host_os"] carries OS-version detail (e.g.
    # "darwin25", "linux-gnu") that the asset-name table does not key on.
    # An OS family this method does not recognize is passed through
    # unchanged, so it deliberately fails the ASSET_NAMES lookup instead of
    # being coerced into a false match.
    def normalize_os(host_os)
      case host_os
      when /darwin/ then "darwin"
      when /linux/ then "linux"
      when /mingw|windows/ then "mingw-ucrt"
      else host_os
      end
    end

    # RubyGems abbreviates the "x86_64" config.guess CPU to "x64" only for
    # Windows platform strings (the "x64-mingw-ucrt" gem platform); every
    # other OS keeps the raw host_cpu value, matching this project's own
    # Gemfile.lock entry "arm64-darwin-25" on an Apple Silicon Mac.
    def normalize_cpu(host_cpu, normalized_os)
      (normalized_os == "mingw-ucrt" && host_cpu == "x86_64") ? "x64" : host_cpu
    end

    # Shared-library extension for host_os alone, independent of whether the
    # specific host_cpu is one hegel-rust publishes a build for. This lets
    # an explicit directory override (step 1) resolve on an otherwise
    # unsupported host (e.g. x86_64-darwin), matching a local libhegel build
    # that always produces the OS-native extension.
    def ext_of_os(host_os)
      case host_os
      when /darwin/ then "dylib"
      when /mingw|windows/ then "dll"
      else "so"
      end
    end

    def unsupported_host_message(host_cpu, host_os)
      "libhegel has no published build for host \"#{host_cpu}-#{host_os}\". " \
        "Set #{LIBRARY_PATH_ENV} to a local libhegel build."
    end

    def missing_bundle_message(asset, gem_dir)
      "libhegel not found: expected #{asset} under #{gem_dir}. " \
        "Set #{LIBRARY_PATH_ENV} to a local libhegel build, or run `rake libhegel:fetch`."
    end
  end
end
