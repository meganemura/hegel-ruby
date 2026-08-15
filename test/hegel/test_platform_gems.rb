# frozen_string_literal: true

require "test_helper"
require "hegel/locate"
require "hegel/libhegel_version"
require "rake"
require "rubygems/package"
require "tmpdir"
require "fileutils"
require "digest"

# lib/tasks/libhegel.rake and lib/tasks/platform_gems.rake are not required
# by the library itself; load them here so their logic is reachable from
# this suite, the same way test/hegel/test_locate.rb loads libhegel.rake on
# its own. Both are loaded (not just platform_gems.rake) so this file stays
# runnable standalone: Hegel::PlatformGems never references
# Hegel::LibhegelFetch, but this suite exercises `rake libhegel:fetch_all`
# too, which needs libhegel.rake's own module.
load File.expand_path("../../lib/tasks/libhegel.rake", __dir__)
load File.expand_path("../../lib/tasks/platform_gems.rake", __dir__)

class TestLibhegelFetchAll < Minitest::Test
  def test_fetch_all_assets_skips_a_present_asset_and_downloads_the_rest
    Dir.mktmpdir do |root|
      version = "0.32.5"
      staged_asset = "libhegel-darwin-arm64.dylib"
      staged_dir = File.join(root, version)
      FileUtils.mkdir_p(staged_dir)
      File.write(File.join(staged_dir, staged_asset), "already here")

      requested = []
      canned = lambda do |url|
        requested << url
        url.end_with?(".sha256") ? "#{Digest::SHA256.hexdigest("bytes")}  x\n" : "bytes"
      end

      results = Hegel::LibhegelFetch.fetch_all_assets(version: version, root: root, downloader: canned)

      assert_equal Hegel::Locate::ASSET_NAMES.size, results.size
      assert_equal "already here", File.read(File.join(staged_dir, staged_asset)),
        "the pre-staged asset must not be overwritten"
      refute requested.any? { |url| url.include?(staged_asset) },
        "must not download #{staged_asset}: it was already present"

      Hegel::Locate::ASSET_NAMES.values.reject { |asset| asset == staged_asset }.each do |asset|
        assert requested.any? { |url| url.include?(asset) }, "expected a request for #{asset}"
      end
    end
  end

  def test_fetch_all_task_installs_and_reports_every_asset
    Hegel::LibhegelFetch.stub :fetch_all_assets, ["/tmp/fake/a.dylib", "/tmp/fake/b.so"] do
      out, _err = capture_io { Rake::Task["libhegel:fetch_all"].invoke }
      assert_includes out, "/tmp/fake/a.dylib"
      assert_includes out, "/tmp/fake/b.so"
    end
  end
end

class TestPlatformGems < Minitest::Test
  def test_base_spec_loads_the_project_gemspec
    spec = Hegel::PlatformGems.base_spec
    assert_equal "hegeltest", spec.name
    assert_equal Gem::Platform::RUBY, spec.platform
  end

  def test_base_spec_bundles_no_libhegel_asset_or_notice
    # This is the spec `rake build` (the ruby-platform gem) also packages
    # from, so this is what "the ruby platform gem carries no engine" means.
    files = Hegel::PlatformGems.base_spec.files
    Hegel::Locate::ASSET_NAMES.each_value do |asset|
      refute_includes files, "lib/hegel/libhegel/#{asset}"
    end
    refute_includes files, "lib/hegel/libhegel/NOTICE-libhegel.txt"
    refute_includes files, "NOTICE-libhegel.txt"
  end

  def test_asset_path_returns_the_staged_path_when_present
    Dir.mktmpdir do |root|
      version = "0.32.5"
      dest_dir = File.join(root, version)
      FileUtils.mkdir_p(dest_dir)
      dest = File.join(dest_dir, "libhegel-darwin-arm64.dylib")
      File.write(dest, "native bytes")

      path = Hegel::PlatformGems.asset_path("arm64-darwin", version: version, root: root)
      assert_equal dest, path
    end
  end

  def test_asset_path_raises_when_not_yet_fetched
    Dir.mktmpdir do |root|
      error = assert_raises(Hegel::Error) do
        Hegel::PlatformGems.asset_path("arm64-darwin", version: "0.32.5", root: root)
      end
      assert_includes error.message, "arm64-darwin"
      assert_includes error.message, "libhegel:fetch_all"
    end
  end

  def test_build_bundles_exactly_this_platforms_asset_and_the_notice
    Dir.mktmpdir do |work|
      asset = File.join(work, "libhegel-darwin-arm64.dylib")
      File.write(asset, "fake arm64-darwin bytes")
      output_dir = File.join(work, "pkg")

      gem_path = Hegel::PlatformGems.build(
        spec: Hegel::PlatformGems.base_spec, platform: "arm64-darwin", asset: asset, output_dir: output_dir
      )

      package = Gem::Package.new(gem_path)
      assert_equal "arm64-darwin", package.spec.platform.to_s
      assert_includes package.spec.files, "lib/hegel/libhegel/libhegel-darwin-arm64.dylib"
      assert_includes package.spec.files, "lib/hegel/libhegel/NOTICE-libhegel.txt"
      assert_includes package.spec.files, "lib/hegel.rb"

      other_assets = Hegel::Locate::ASSET_NAMES.values - ["libhegel-darwin-arm64.dylib"]
      other_assets.each do |other|
        refute_includes package.spec.files, "lib/hegel/libhegel/#{other}"
      end

      extracted = File.join(work, "extracted")
      package.extract_files(extracted)
      assert_equal "fake arm64-darwin bytes",
        File.read(File.join(extracted, "lib/hegel/libhegel/libhegel-darwin-arm64.dylib"))
      assert_includes File.read(File.join(extracted, "lib/hegel/libhegel/NOTICE-libhegel.txt")), "Antithesis, LLC"
    end
  end

  def test_build_all_produces_all_five_platform_gems_from_fetched_assets
    Dir.mktmpdir do |work|
      version = "0.32.5"
      asset_dir = File.join(work, version)
      FileUtils.mkdir_p(asset_dir)
      Hegel::Locate::ASSET_NAMES.each_value do |asset|
        File.write(File.join(asset_dir, asset), "fake bytes for #{asset}")
      end
      output_dir = File.join(work, "pkg")

      gem_paths = Hegel::PlatformGems.build_all(
        spec: Hegel::PlatformGems.base_spec, version: version, root: work, output_dir: output_dir
      )

      assert_equal Hegel::Locate::ASSET_NAMES.size, gem_paths.size
      packages = gem_paths.map { |path| Gem::Package.new(path) }
      built_platforms = packages.map { |package| package.spec.platform.to_s }
      assert_equal Hegel::Locate::ASSET_NAMES.keys.sort, built_platforms.sort

      packages.each do |package|
        own_asset = Hegel::Locate::ASSET_NAMES.fetch(package.spec.platform.to_s)
        bundled_assets = package.spec.files.grep(%r{\Alib/hegel/libhegel/libhegel-}).map { |f| File.basename(f) }
        assert_equal [own_asset], bundled_assets
      end
    end
  end

  def test_build_all_raises_before_writing_when_an_asset_is_missing
    # Overrides only root: (an empty tmpdir), so the default expressions for
    # spec:, version:, notice:, and output_dir: all still run. The first
    # platform's asset_path lookup raises before build (and its own
    # output_dir:) is ever reached, so this never touches the real pkg/.
    Dir.mktmpdir do |root|
      error = assert_raises(Hegel::Error) do
        Hegel::PlatformGems.build_all(root: root)
      end
      assert_includes error.message, "libhegel:fetch_all"
    end
  end

  def test_platform_gems_build_task_builds_and_reports_every_platform
    Hegel::PlatformGems.stub :build_all, ["/tmp/fake/a.gem", "/tmp/fake/b.gem"] do
      out, _err = capture_io { Rake::Task["platform_gems:build"].invoke }
      assert_includes out, "/tmp/fake/a.gem"
      assert_includes out, "/tmp/fake/b.gem"
    end
  end
end
