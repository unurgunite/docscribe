# frozen_string_literal: true

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'docscribe'
require 'support/header_regex'

module InlineHelper
  def inline(code, config: Docscribe::Config.new({}))
    Docscribe::InlineRewriter.insert_comments(code, config: config)
  end
end

RSpec.configure do |config|
  config.include HeaderRegex
  config.include InlineHelper
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
