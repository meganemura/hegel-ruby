# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "rubygems/package"
require_relative "../hegel/locate"
require_relative "../hegel/libhegel_version"
require_relative "../hegel/errors"

# Packages this gem for the five platforms hegel-rust publishes a libhegel
# build for (see Hegel::Locate::ASSET_NAMES), on top of the platform-
# independent "ruby" gem `rake build` already produces. A platform gem
# differs from that ruby gem in exactly two ways: spec.platform names the
# platform, and lib/hegel/libhegel/ (Hegel::Locate::GEM_LIBHEGEL_DIR) carries
# that platform's asset plus libhegel's own MIT notice.
#
# Building happens in a temporary staging directory copied from the working
# tree, rather than in the working tree itself. Gem::Package reads every
# spec.files entry relative to the process's current directory, and staging
# keeps a five-platform build from ever writing a binary into the repository.
#
# This file does not reference Hegel::LibhegelFetch (lib/tasks/libhegel.rake):
# it redeclares the tmp/libhegel/<version>/<asset> layout as its own
# ASSET_ROOT so it loads and tests on its own, the same way libhegel.rake
# does not depend on this file existing.
module Hegel
  module PlatformGems
    ROOT = File.expand_path("../..", __dir__)
    GEMSPEC_PATH = File.join(ROOT, "hegeltest.gemspec")
    NOTICE_PATH = File.join(ROOT, "NOTICE-libhegel.txt")
    DEFAULT_OUTPUT_DIR = File.join(ROOT, "pkg")
    ASSET_ROOT = File.join(ROOT, "tmp", "libhegel")

    # Where a platform gem carries its asset and notice, relative to the gem
    # root. Matches Hegel::Locate::GEM_LIBHEGEL_DIR, the directory Locate
    # resolves the bundled copy from once the gem is installed.
    BUNDLE_DIR = "lib/hegel/libhegel"

    module_function

    # The gemspec, loaded fresh each call: Gem::Specification.load caches by
    # path, so a caller who wants today's `git ls-files` (after adding a new
    # file, say) must not memoize this across process lifetimes on their own.
    def base_spec
      Gem::Specification.load(GEMSPEC_PATH)
    end

    # The asset `rake libhegel:fetch_all` (or fetch_host_asset, for the
    # host's own platform) already staged for `platform`, or raises if it has
    # not run yet.
    def asset_path(platform, version: Hegel::LIBHEGEL_VERSION, root: ASSET_ROOT)
      asset = Hegel::Locate::ASSET_NAMES.fetch(platform)
      path = File.join(root, version, asset)
      return path if File.file?(path)

      raise Hegel::Error, "no fetched libhegel asset for #{platform} at #{path}. Run `rake libhegel:fetch_all` first."
    end

    # Builds one platform's gem into `output_dir`, from `spec`'s file set plus
    # that platform's asset and the libhegel notice, and returns the path to
    # the built .gem. `spec`, `asset`, and `notice` are injectable so a test
    # can verify the package's contents with fake files, without touching the
    # real working tree or the network.
    def build(spec:, platform:, asset:, notice: NOTICE_PATH, output_dir: DEFAULT_OUTPUT_DIR)
      platform_spec = spec.dup
      platform_spec.platform = Gem::Platform.new(platform)

      extra_files = {
        "#{BUNDLE_DIR}/#{File.basename(asset)}" => asset,
        "#{BUNDLE_DIR}/#{File.basename(notice)}" => notice
      }
      platform_spec.files = spec.files + extra_files.keys

      FileUtils.mkdir_p(output_dir)
      gem_path = File.join(output_dir, "#{platform_spec.full_name}.gem")

      Dir.mktmpdir do |stage|
        spec.files.each { |relative| stage_copy(stage, relative, File.join(ROOT, relative)) }
        extra_files.each { |relative, source| stage_copy(stage, relative, source) }

        Dir.chdir(stage) { Gem::Package.build(platform_spec, false, false, gem_path) }
      end

      gem_path
    end

    def stage_copy(stage, relative, source)
      dest = File.join(stage, relative)
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(source, dest)
    end

    # Builds every published platform's gem, each from an asset
    # `rake libhegel:fetch_all` already staged under `root`.
    def build_all(spec: base_spec, version: Hegel::LIBHEGEL_VERSION, root: ASSET_ROOT, notice: NOTICE_PATH,
      output_dir: DEFAULT_OUTPUT_DIR)
      Hegel::Locate::ASSET_NAMES.each_key.map do |platform|
        build(spec: spec, platform: platform, asset: asset_path(platform, version: version, root: root),
          notice: notice, output_dir: output_dir)
      end
    end
  end
end

namespace :platform_gems do
  desc "Build the hegeltest gem for every platform hegel-rust publishes libhegel for, " \
    "from assets already fetched by `rake libhegel:fetch_all`"
  task :build do
    Hegel::PlatformGems.build_all.each { |path| puts "built: #{path}" }
  end
end
