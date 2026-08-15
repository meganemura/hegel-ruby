# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require_relative "../hegel/locate"
require_relative "../hegel/libhegel_version"

# Downloads the pinned libhegel release asset for the host platform into
# tmp/libhegel/<version>/, verifying it against the published SHA-256 before
# installing it. This is the one place in the codebase allowed to touch the
# network (see lib/hegel/locate.rb's module comment); everything a test run
# needs is fetched here ahead of time, not at resolution time.
module Hegel
  module LibhegelFetch
    RELEASE_BASE = "https://github.com/hegeldev/hegel-rust/releases/download"
    DEFAULT_ROOT = File.expand_path("../../tmp/libhegel", __dir__)

    module_function

    # Fetches the host's pinned asset into <root>/<version>/<asset>,
    # skipping the download if it is already there. `downloader` is
    # injectable so the orchestration (skip-if-present, checksum parsing,
    # mismatch handling) is testable without the network; it defaults to a
    # real HTTP GET.
    def fetch_host_asset(version: Hegel::LIBHEGEL_VERSION, host_cpu: RbConfig::CONFIG["host_cpu"],
      host_os: RbConfig::CONFIG["host_os"], root: DEFAULT_ROOT, downloader: method(:http_get))
      asset = Hegel::Locate.asset_name(host_cpu: host_cpu, host_os: host_os)
      dest = File.join(root, version, asset)
      return dest if File.file?(dest)

      base = "#{RELEASE_BASE}/v#{version}"
      bytes = downloader.call("#{base}/#{asset}")
      checksum_line = downloader.call("#{base}/#{asset}.sha256")
      verify_and_install(bytes, expected_sha256(checksum_line), dest)
    end

    # The published checksum file is one line, "<hex>  <filename>"; the hex
    # digest is its first whitespace-separated token.
    def expected_sha256(checksum_line)
      checksum_line.split.first
    end

    # Verifies `bytes` against `expected_hex` and, only on a match, writes
    # them to `dest` (via a same-directory temp file, renamed into place so
    # a reader never sees a partial file). On mismatch, raises without ever
    # touching disk, so a failed fetch never leaves a corrupt file behind.
    def verify_and_install(bytes, expected_hex, dest)
      actual_hex = Digest::SHA256.hexdigest(bytes)
      if actual_hex != expected_hex
        raise Hegel::Error, "SHA-256 mismatch for #{File.basename(dest)}: expected #{expected_hex}, got #{actual_hex}"
      end

      FileUtils.mkdir_p(File.dirname(dest))
      tmp = "#{dest}.#{Process.pid}.partial"
      File.binwrite(tmp, bytes)
      File.rename(tmp, dest)
      dest
    end

    # Fetches every published platform's asset (see Hegel::Locate::ASSET_NAMES),
    # not just the host's, into <root>/<version>/<asset>: this is what
    # `rake libhegel:fetch_all` stages the five platform gems from. Repeats
    # fetch_host_asset's steps per asset rather than delegating to it,
    # because delegating would mean computing a host_cpu/host_os pair for
    # each published platform just to have asset_name recompute the asset
    # name it already is.
    def fetch_all_assets(version: Hegel::LIBHEGEL_VERSION, root: DEFAULT_ROOT, downloader: method(:http_get))
      base = "#{RELEASE_BASE}/v#{version}"
      Hegel::Locate::ASSET_NAMES.values.map do |asset|
        dest = File.join(root, version, asset)
        next dest if File.file?(dest)

        bytes = downloader.call("#{base}/#{asset}")
        checksum_line = downloader.call("#{base}/#{asset}.sha256")
        verify_and_install(bytes, expected_sha256(checksum_line), dest)
      end
    end

    # Minimal redirect-following GET: GitHub release assets serve a 302 to
    # the actual blob storage host. `getter` is injectable (defaulting to a
    # real Net::HTTP call) so the redirect/success/error branches are
    # testable with hand-built responses, no network involved.
    def http_get(url, redirects: 5, getter: Net::HTTP.method(:get_response))
      response = getter.call(URI(url))
      case response
      when Net::HTTPRedirection
        raise Hegel::Error, "too many redirects for #{url}" if redirects <= 0

        http_get(response["location"], redirects: redirects - 1, getter: getter)
      when Net::HTTPSuccess
        response.body
      else
        raise Hegel::Error, "HTTP #{response.code} for #{url}"
      end
    end
  end
end

namespace :libhegel do
  desc "Download the pinned libhegel build for this host into tmp/libhegel/<version>/"
  task :fetch do
    dest = Hegel::LibhegelFetch.fetch_host_asset
    puts "libhegel: #{dest}"
  end

  desc "Download the pinned libhegel build for every published platform into tmp/libhegel/<version>/, " \
    "for `rake platform_gems:build` to package"
  task :fetch_all do
    Hegel::LibhegelFetch.fetch_all_assets.each { |dest| puts "libhegel: #{dest}" }
  end
end
