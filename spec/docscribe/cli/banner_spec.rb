# frozen_string_literal: true

require 'docscribe/cli'

CLI_DIR = File.expand_path('../../../lib/docscribe/cli', __dir__)
EXCLUDE = %w[run.rb config_builder.rb formatters.rb].freeze

RSpec.describe Docscribe::CLI do
  include BannerSpecHelper

  describe 'BANNER constant' do
    Dir["#{CLI_DIR}/*.rb"].each do |file|
      next if File.basename(file).start_with?('_') || EXCLUDE.include?(File.basename(file))

      it "defines BANNER in #{File.basename(file)}" do
        expect(File.read(file)).to include('BANNER = <<~')
      end

      it "has BANNER constant in #{File.basename(file)}" do
        require "docscribe/cli/#{File.basename(file, '.rb')}"
        expect(Object.const_get(BannerSpecHelper.module_name(file))).to be_const_defined(:BANNER)
      end
    end
  end
end
