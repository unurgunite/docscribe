# frozen_string_literal: true

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'docscribe'
Dir['./spec/support/*.rb'].sort.each { |file| require file }

module InlineHelper
  # +InlineHelper#inline+ -> Object
  #
  # Method documentation.
  #
  # @param [Object] code Param documentation.
  # @param [Config] config Param documentation.
  # @return [Object]
  def inline(code, config: Docscribe::Config.new({}), strategy: :safe)
    Docscribe::InlineRewriter.insert_comments(code, strategy: strategy, config: config)
  end
end

RSpec.configure do |config|
  config.include HeaderRegex
  config.include InlineHelper
  config.include ParamTag
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
