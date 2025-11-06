# frozen_string_literal: true

require_relative 'lib/stingray_docs_internal/version'

Gem::Specification.new do |spec|
  spec.name = 'stingray_docs'
  spec.version = StingrayDocsInternal::VERSION
  spec.authors = ['unurgunite']
  spec.email = ['senpaiguru1488@gmail.com']

  spec.summary = 'This gem is used only for internal purposes in Stingray Technical LTD.'
  spec.description = 'Gem for generating internal documentation in Stingray Technical LTD.'
  spec.homepage = 'https://github.com/unurgunite/stingray_docs_internal'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/unurgunite/stingray_docs_internal'
  spec.metadata['changelog_uri'] = 'https://github.com/unurgunite/stingray_docs_internal/blob/master/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'parser', '>= 3.0'
  spec.add_dependency 'yard', '>= 0.9.34'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-sorted_methods_by_call'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
