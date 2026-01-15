# frozen_string_literal: true

require_relative 'lib/docscribe/version'

Gem::Specification.new do |spec|
  spec.name = 'docscribe'
  spec.version = Docscribe::VERSION
  spec.authors = ['unurgunite']
  spec.email = ['senpaiguru1488@gmail.com']

  spec.summary = 'Autogenerate documentation for Ruby code with YARD syntax.'
  spec.homepage = 'https://github.com/unurgunite/docscribe'
  spec.required_ruby_version = '>= 2.7'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/unurgunite/docscribe'
  spec.metadata['changelog_uri'] = 'https://github.com/unurgunite/docscribe/blob/master/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select do |f|
      f.start_with?('lib/', 'exe/') ||
        %w[README.md LICENSE.txt].include?(f)
    end
  end

  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'parser', '>= 3.3'
  spec.add_dependency 'prism', '~> 1.8'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-rake'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'rubocop-sorted_methods_by_call'
  spec.add_development_dependency 'yard', '>= 0.9.38'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
