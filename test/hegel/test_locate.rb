# frozen_string_literal: true

require "test_helper"
require "hegel/locate"
require "hegel/libhegel_version"
require "tmpdir"
require "rake"

# lib/tasks/libhegel.rake is not required by the library itself (only the
# `rake libhegel:fetch` task loads it); load it here so its logic is
# reachable from this suite, which is what puts its logic under the same
# coverage bar as the rest of lib/.
load File.expand_path("../../lib/tasks/libhegel.rake", __dir__)

class TestLocate < Minitest::Test
  SUPPORTED_HOSTS = {
    %w[arm64 darwin25] => "libhegel-darwin-arm64.dylib",
    %w[x86_64 linux-gnu] => "libhegel-linux-amd64.so",
    %w[aarch64 linux-gnu] => "libhegel-linux-arm64.so",
    %w[x86_64 mingw-ucrt] => "libhegel-windows-amd64.dll",
    %w[aarch64 mingw-ucrt] => "libhegel-windows-arm64.dll"
  }.freeze

  def test_asset_name_covers_every_supported_host
    SUPPORTED_HOSTS.each do |(cpu, os), asset|
      assert_equal asset, Hegel::Locate.asset_name(host_cpu: cpu, host_os: os)
    end
  end

  def test_asset_name_raises_for_unsupported_intel_mac
    error = assert_raises(Hegel::Error) do
      Hegel::Locate.asset_name(host_cpu: "x86_64", host_os: "darwin25")
    end
    assert_includes error.message, "HEGEL_LIBHEGEL_PATH"
  end

  def test_asset_name_raises_for_a_wholly_unrecognized_os
    error = assert_raises(Hegel::Error) do
      Hegel::Locate.asset_name(host_cpu: "x86_64", host_os: "freebsd14")
    end
    assert_includes error.message, "HEGEL_LIBHEGEL_PATH"
  end

  def test_resolve_returns_the_env_override_file_as_is
    path = Hegel::Locate.resolve(
      env: {"HEGEL_LIBHEGEL_PATH" => "/opt/custom/libhegel.dylib"},
      host_cpu: "arm64", host_os: "darwin25"
    )
    assert_equal "/opt/custom/libhegel.dylib", path
  end

  def test_resolve_treats_an_empty_override_as_unset
    Dir.mktmpdir do |gem_dir|
      asset = File.join(gem_dir, "libhegel-darwin-arm64.dylib")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(
        env: {"HEGEL_LIBHEGEL_PATH" => ""},
        host_cpu: "arm64", host_os: "darwin25", gem_dir: gem_dir
      )
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_finds_the_release_asset_name
    # This is the name `rake libhegel:fetch` itself installs, e.g.
    # tmp/libhegel/<version>/libhegel-darwin-arm64.dylib.
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel-darwin-arm64.dylib")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_finds_the_cargo_output_name
    # hegel-c/Cargo.toml declares `[lib] name = "hegel_c"`; the hegel-cpp
    # README points HEGEL_LIBHEGEL_LIBRARY at a path ending in this name.
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel_c.dylib")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_finds_the_renamed_copy
    # The hegel-go and hegel-ocaml READMEs describe placing a copy under
    # this basename.
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel.dylib")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_prefers_the_release_asset_name
    Dir.mktmpdir do |dir|
      release_asset = File.join(dir, "libhegel-darwin-arm64.dylib")
      File.write(release_asset, "native bytes")
      File.write(File.join(dir, "libhegel_c.dylib"), "native bytes")
      File.write(File.join(dir, "libhegel.dylib"), "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      assert_equal release_asset, path
    end
  end

  def test_resolve_directory_override_prefers_the_cargo_output_name_over_the_renamed_copy
    Dir.mktmpdir do |dir|
      cargo_output = File.join(dir, "libhegel_c.dylib")
      File.write(cargo_output, "native bytes")
      File.write(File.join(dir, "libhegel.dylib"), "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      assert_equal cargo_output, path
    end
  end

  def test_resolve_directory_override_skips_the_release_asset_name_when_the_host_is_unsupported
    # x86_64-darwin has no published release asset, but a directory override
    # is how such a host points at a self-built library, so the other two
    # candidates must still work.
    Dir.mktmpdir do |dir|
      cargo_output = File.join(dir, "libhegel_c.dylib")
      File.write(cargo_output, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "x86_64", host_os: "darwin25")
      assert_equal cargo_output, path
    end
  end

  def test_resolve_directory_override_finds_the_renamed_copy_when_the_host_is_unsupported
    Dir.mktmpdir do |dir|
      renamed_copy = File.join(dir, "libhegel.dylib")
      File.write(renamed_copy, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "x86_64", host_os: "darwin25")
      assert_equal renamed_copy, path
    end
  end

  def test_resolve_directory_override_uses_dll_on_windows
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel.dll")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "x86_64", host_os: "mingw-ucrt")
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_uses_so_elsewhere
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel.so")
      File.write(asset, "native bytes")

      path = Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "x86_64", host_os: "linux-gnu")
      assert_equal asset, path
    end
  end

  def test_resolve_directory_override_raises_when_none_of_the_three_names_are_present
    Dir.mktmpdir do |dir|
      error = assert_raises(Hegel::Error) do
        Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "arm64", host_os: "darwin25")
      end

      assert_includes error.message, dir
      assert_includes error.message, "libhegel-darwin-arm64.dylib"
      assert_includes error.message, "libhegel_c.dylib"
      assert_includes error.message, "libhegel.dylib"
    end
  end

  def test_resolve_directory_override_raises_without_the_release_asset_name_when_the_host_is_unsupported
    # The candidate list omits the release asset name entirely for an
    # unsupported host, so the error message must not mention it either.
    Dir.mktmpdir do |dir|
      error = assert_raises(Hegel::Error) do
        Hegel::Locate.resolve(env: {"HEGEL_LIBHEGEL_PATH" => dir}, host_cpu: "x86_64", host_os: "darwin25")
      end

      assert_includes error.message, dir
      assert_includes error.message, "libhegel_c.dylib"
      assert_includes error.message, "libhegel.dylib"
      refute_includes error.message, "libhegel-darwin-arm64.dylib"
    end
  end

  def test_resolve_never_consults_the_bundle_when_overridden
    finder_called = false
    finder = lambda do |_dir, _asset|
      finder_called = true
      "should never be reached"
    end

    path = Hegel::Locate.resolve(
      env: {"HEGEL_LIBHEGEL_PATH" => "/opt/custom/libhegel.dylib"},
      host_cpu: "arm64", host_os: "darwin25", finder: finder
    )

    assert_equal "/opt/custom/libhegel.dylib", path
    refute finder_called, "the gem-bundled finder must not run when the env override is set"
  end

  def test_resolve_uses_the_gem_bundled_finder_when_the_host_is_supported
    found = "/gem/libhegel/libhegel-darwin-arm64.dylib"
    finder = ->(dir, asset) { (dir == "/gem/libhegel" && asset == "libhegel-darwin-arm64.dylib") ? found : nil }

    path = Hegel::Locate.resolve(env: {}, host_cpu: "arm64", host_os: "darwin25", gem_dir: "/gem/libhegel", finder: finder)
    assert_equal found, path
  end

  def test_resolve_raises_when_the_host_is_supported_but_nothing_is_bundled
    error = assert_raises(Hegel::Error) do
      Hegel::Locate.resolve(env: {}, host_cpu: "arm64", host_os: "darwin25", gem_dir: "/nowhere", finder: ->(*) {})
    end
    assert_includes error.message, "HEGEL_LIBHEGEL_PATH"
    assert_includes error.message, "libhegel-darwin-arm64.dylib"
  end

  def test_resolve_raises_for_an_unsupported_host_before_touching_the_filesystem
    finder_called = false
    finder = lambda do |_dir, _asset|
      finder_called = true
      "should never be reached"
    end

    error = assert_raises(Hegel::Error) do
      Hegel::Locate.resolve(env: {}, host_cpu: "x86_64", host_os: "darwin25", finder: finder)
    end

    assert_includes error.message, "HEGEL_LIBHEGEL_PATH"
    refute finder_called, "an unsupported host must be reported before any bundle lookup"
  end

  def test_default_finder_finds_a_present_asset
    Dir.mktmpdir do |dir|
      asset = File.join(dir, "libhegel-darwin-arm64.dylib")
      File.write(asset, "native bytes")
      assert_equal asset, Hegel::Locate::DEFAULT_FINDER.call(dir, "libhegel-darwin-arm64.dylib")
    end
  end

  def test_default_finder_returns_nil_for_a_missing_asset
    Dir.mktmpdir do |dir|
      assert_nil Hegel::Locate::DEFAULT_FINDER.call(dir, "libhegel-darwin-arm64.dylib")
    end
  end

  def test_resolve_exercises_its_gem_dir_and_finder_defaults
    # Omits gem_dir: and finder: so their default-argument expressions
    # (GEM_LIBHEGEL_DIR, DEFAULT_FINDER) run; the host is unsupported so the
    # call still raises without depending on this machine's real bundle.
    error = assert_raises(Hegel::Error) do
      Hegel::Locate.resolve(env: {}, host_cpu: "x86_64", host_os: "darwin25")
    end
    assert_includes error.message, "HEGEL_LIBHEGEL_PATH"
  end

  def test_libhegel_version_is_a_semver_string
    assert_match(/\A\d+\.\d+\.\d+\z/, Hegel::LIBHEGEL_VERSION)
  end
end

class TestLibhegelFetch < Minitest::Test
  def test_expected_sha256_takes_the_first_token_of_the_checksum_line
    line = "f756966b9c045af344d5d1e3279036fea99d325dd102b3589ff26db28e91c54f  libhegel-darwin-arm64.dylib\n"
    assert_equal "f756966b9c045af344d5d1e3279036fea99d325dd102b3589ff26db28e91c54f",
      Hegel::LibhegelFetch.expected_sha256(line)
  end

  def test_verify_and_install_writes_the_file_on_a_checksum_match
    Dir.mktmpdir do |dir|
      dest = File.join(dir, "libhegel-darwin-arm64.dylib")
      bytes = "native bytes"
      hex = Digest::SHA256.hexdigest(bytes)

      result = Hegel::LibhegelFetch.verify_and_install(bytes, hex, dest)

      assert_equal dest, result
      assert_equal bytes, File.read(dest)
    end
  end

  def test_verify_and_install_raises_and_leaves_no_file_on_a_mismatch
    Dir.mktmpdir do |dir|
      version_dir = File.join(dir, "0.32.5")
      dest = File.join(version_dir, "libhegel-darwin-arm64.dylib")

      error = assert_raises(Hegel::Error) do
        Hegel::LibhegelFetch.verify_and_install("native bytes", "0" * 64, dest)
      end

      assert_includes error.message, "SHA-256 mismatch"
      refute File.exist?(dest)
      refute File.directory?(version_dir), "a mismatch must not even create the version directory"
    end
  end

  def test_fetch_host_asset_skips_the_download_when_already_present
    Dir.mktmpdir do |root|
      dest_dir = File.join(root, "0.32.5")
      FileUtils.mkdir_p(dest_dir)
      dest = File.join(dest_dir, "libhegel-darwin-arm64.dylib")
      File.write(dest, "already here")
      flunking_downloader = ->(url) { flunk("must not download #{url} when the asset is already present") }

      result = Hegel::LibhegelFetch.fetch_host_asset(
        version: "0.32.5", host_cpu: "arm64", host_os: "darwin25", root: root, downloader: flunking_downloader
      )

      assert_equal dest, result
    end
  end

  def test_fetch_host_asset_downloads_and_installs_on_a_cache_miss
    Dir.mktmpdir do |root|
      bytes = "native bytes"
      hex = Digest::SHA256.hexdigest(bytes)
      canned = lambda do |url|
        url.end_with?(".sha256") ? "#{hex}  libhegel-darwin-arm64.dylib\n" : bytes
      end

      result = Hegel::LibhegelFetch.fetch_host_asset(
        version: "0.32.5", host_cpu: "arm64", host_os: "darwin25", root: root, downloader: canned
      )

      assert_equal File.join(root, "0.32.5", "libhegel-darwin-arm64.dylib"), result
      assert_equal bytes, File.read(result)
    end
  end

  def test_fetch_host_asset_raises_on_a_checksum_mismatch
    Dir.mktmpdir do |root|
      canned = lambda do |url|
        url.end_with?(".sha256") ? "#{"0" * 64}  libhegel-darwin-arm64.dylib\n" : "native bytes"
      end

      assert_raises(Hegel::Error) do
        Hegel::LibhegelFetch.fetch_host_asset(
          version: "0.32.5", host_cpu: "arm64", host_os: "darwin25", root: root, downloader: canned
        )
      end
      refute File.exist?(File.join(root, "0.32.5"))
    end
  end

  def test_http_get_returns_the_body_on_success
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    def ok.body
      "payload bytes"
    end
    getter = ->(_uri) { ok }

    assert_equal "payload bytes", Hegel::LibhegelFetch.http_get("https://example.com/a", getter: getter)
  end

  def test_http_get_follows_a_redirect_then_succeeds
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    def ok.body
      "payload bytes"
    end
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["location"] = "https://example.com/redirected"
    calls = []
    getter = lambda do |uri|
      calls << uri.to_s
      (calls.length == 1) ? redirect : ok
    end

    result = Hegel::LibhegelFetch.http_get("https://example.com/a", getter: getter)

    assert_equal "payload bytes", result
    assert_equal ["https://example.com/a", "https://example.com/redirected"], calls
  end

  def test_http_get_raises_after_too_many_redirects
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["location"] = "https://example.com/loop"
    getter = ->(_uri) { redirect }

    error = assert_raises(Hegel::Error) do
      Hegel::LibhegelFetch.http_get("https://example.com/a", redirects: 1, getter: getter)
    end
    assert_includes error.message, "too many redirects"
  end

  def test_http_get_raises_on_a_non_success_non_redirect_response
    not_found = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    getter = ->(_uri) { not_found }

    error = assert_raises(Hegel::Error) do
      Hegel::LibhegelFetch.http_get("https://example.com/a", getter: getter)
    end
    assert_includes error.message, "404"
  end
end

class TestLibhegelFetchTask < Minitest::Test
  def test_the_fetch_task_installs_and_reports_the_resolved_path
    Hegel::LibhegelFetch.stub :fetch_host_asset, "/tmp/fake/libhegel.dylib" do
      out, _err = capture_io { Rake::Task["libhegel:fetch"].invoke }
      assert_includes out, "/tmp/fake/libhegel.dylib"
    end
  end
end
