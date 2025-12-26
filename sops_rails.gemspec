# frozen_string_literal: true

require_relative "lib/sops_rails/version"

Gem::Specification.new do |spec|
  spec.name = "sops_rails"
  spec.version = SopsRails::VERSION
  spec.authors = ["Tomáš Landovský"]
  spec.email = ["landovsky@gmail.com"]

  spec.summary = "SOPS encryption support for Rails credentials"
  spec.description = "Native Mozilla SOPS encryption for Rails applications. " \
                     "Manage secrets with visible YAML structure and team-friendly age keys."
  spec.homepage = "https://github.com/landovsky/sops_rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/landovsky/sops_rails"
  spec.metadata["changelog_uri"] = "https://github.com/landovsky/sops_rails/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
