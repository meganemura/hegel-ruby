# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "hegeltest"

  # Read the version rather than requiring the file that defines it. Bundler
  # evaluates this gemspec while it sets up the load path, so a
  # `require_relative` here would run library code before anything a test
  # process starts -- including coverage measurement, which would then report
  # an already-loaded file as never executed. A mismatch fails the build
  # loudly, because a nil version is not a version.
  spec.version = File.read(File.expand_path("lib/hegel/version.rb", __dir__))
    .slice(/VERSION\s*=\s*"([^"]+)"/, 1)
  spec.authors = ["meganemura"]
  spec.email = ["meganemura@users.noreply.github.com"]

  spec.summary = "Property-based testing for Ruby, built on Hypothesis"
  spec.description = <<~DESCRIPTION
    An unofficial Ruby implementation of the Hegel protocol. Hegel is a
    property-based testing framework based on Hypothesis. This gem drives
    libhegel, the same native engine that backs the Rust, Go, TypeScript,
    Java, OCaml, and C++ implementations.
  DESCRIPTION
  spec.homepage = "https://github.com/meganemura/hegel-ruby"
  spec.license = "MIT"

  # 3.3 is the oldest Ruby that is not end-of-life, and the oldest that ships
  # Prism as a default gem. Hegel parses the caller's source with Prism to name
  # drawn values in failure reports, so the floor and the feature agree.
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  #
  # The reject list drops development files, and it drops the coding-agent
  # instructions with them. Those instructions describe how to work on this
  # repository, so they mean nothing to somebody who installed the gem, and
  # `git ls-files` would otherwise package every one of them. hegel-rust
  # excludes `/.agents`, `/.claude`, and `/AGENTS.md` from its own crate for
  # the same reason.
  #
  # `.claude-plugin/` is rejected too, but `skills/` is not: `skills/`
  # is this gem's own payload for whoever installs it, while
  # `.claude-plugin/` only points the Claude Code marketplace at this git
  # repository, which an installed gem is not.
  # NOTICE-libhegel.txt is rejected here too: it carries libhegel's own MIT
  # notice, which only means something once a platform gem bundles the
  # binary it covers. lib/tasks/platform_gems.rake injects it into each of
  # the five platform gems directly, so it never needs to reach this
  # platform-independent ("ruby") gem's own file list.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml justfile .claude/ CLAUDE.md
          .claude-plugin/ NOTICE-libhegel.txt])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # The ffi gem opens libhegel and calls its C ABI (see docs/adr/0013). The
  # floor is 1.17.4: ADR 0013's own measurement is what confirmed this
  # version publishes precompiled binaries for every platform this gem
  # targets, so an ordinary install still compiles nothing. The constraint
  # stays pessimistic rather than exact, matching how this gemspec already
  # treats every other runtime dependency; Gemfile.lock is what pins the
  # exact version this project builds and tests against.
  spec.add_dependency "ffi", "~> 1.17", ">= 1.17.4"
end
