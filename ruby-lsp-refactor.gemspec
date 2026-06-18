# frozen_string_literal: true

require_relative "lib/ruby/lsp/refactor/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-lsp-refactor"
  spec.version = Ruby::Lsp::Refactor::VERSION
  spec.authors = ["Aboobacker MK"]
  spec.email = ["aboobackervyd@gmail.com"]

  spec.summary = "AST-driven refactoring code actions for the ruby-lsp ecosystem."
  spec.description = "A ruby-lsp add-on that provides safe, AST-driven refactoring " \
                     "operations (post-conditional conversion, inline variable, etc.) " \
                     "natively within any LSP-supported IDE."
  spec.homepage = "https://github.com/tachyons/ruby-lsp-refactor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prism",    ">= 0.29"
  spec.add_dependency "ruby-lsp", ">= 0.17", "< 2"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake",     "~> 13.0"
  spec.add_development_dependency "rubocop",  "~> 1.21"
end
