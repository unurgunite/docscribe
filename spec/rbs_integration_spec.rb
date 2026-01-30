# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS integration' do
  it 'uses RBS types for params and return when enabled' do
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    Dir.mktmpdir do |dir|
      sig = File.join(dir, 'sig')
      FileUtils.mkdir_p(sig)

      File.write(File.join(sig, 'demo.rbs'), <<~RBS)
        class Demo
          def foo: (verbose: bool, options: ::Hash[::Symbol, untyped]) -> ::Integer
        end
      RBS

      conf = Docscribe::Config.new(
        'rbs' => { 'enabled' => true, 'sig_dirs' => [sig] }
      )

      code = <<~RUBY
        class Demo
          def foo(verbose: true, options: {}); 0; end
        end
      RUBY

      out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

      expect(out).to include('@param [Boolean] verbose')
      expect(out).to include('@param [Hash<Symbol, Object>] options')
      expect(out).to include('@return [Integer]')
    end
  end
end
