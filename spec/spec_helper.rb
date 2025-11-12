# frozen_string_literal: true

require 'docscribe'
require 'support/header_regex'

module InlineHelper
  def inline(code)
    Docscribe::InlineRewriter.insert_comments(code)
  end
end

RSpec.configure do |config|
  config.include HeaderRegex
  config.include InlineHelper
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
