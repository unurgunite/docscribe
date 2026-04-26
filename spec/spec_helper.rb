# frozen_string_literal: true

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'docscribe'
Dir['./spec/support/*.rb'].sort.each { |file| require file }

module InlineHelper
  # Run Docscribe's inline rewriter on +code+ with the given configuration and strategy.
  #
  # Defaults to safe mode and an empty config when no arguments are provided.
  #
  # @param [String] code Ruby source code to rewrite
  # @param [Docscribe::Config, nil] config configuration (defaults to empty)
  # @param [Symbol] strategy rewrite strategy (:safe or :aggressive)
  # @return [String] rewritten source code
  def inline(code, config: Docscribe::Config.new({}), strategy: :safe)
    Docscribe::InlineRewriter.insert_comments(code, strategy: strategy, config: config)
  end
end

RSpec.configure do |config|
  config.include HeaderRegex
  config.include InlineHelper
  config.include ParamTag
  config.include ExeHelper
  config.include RbsHelper
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
