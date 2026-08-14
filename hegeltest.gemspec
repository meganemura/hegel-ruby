# frozen_string_literal: true

require_relative "lib/hegel/version"

Gem::Specification.new do |spec|
  spec.name = "hegeltest"
  spec.version = Hegel::VERSION
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
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml justfile .claude/ CLAUDE.md])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Fiddle opens libhegel and calls its C ABI. The constraint stays loose on
  # purpose: fiddle publishes source-only gems, so a constraint that excludes
  # the fiddle a Ruby ships with would make bundler build fiddle from source
  # and put a compiler back in the install path. Ruby 3.3 ships 1.1.2, 3.4
  # ships 1.1.6, and 4.0 ships 1.1.8.
  spec.add_dependency "fiddle", "~> 1.1"
end
