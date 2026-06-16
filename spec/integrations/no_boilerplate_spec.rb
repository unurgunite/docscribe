# frozen_string_literal: true

require 'open3'
require 'tmpdir'

RSpec.describe Docscribe::InlineRewriter do
  describe 'aggressive mode (default) — boilerplate present' do
    subject(:out) { inline(code, strategy: :aggressive) }

    let(:code) do
      <<~RUBY
        class Demo
          def greet(name)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'inserts method and param default messages', :aggregate_failures do
      expect(out).to include('Generated method description.')
      expect(out).to include('Generated param description.')
    end
  end

  describe 'aggressive mode with no_boilerplate via config' do
    subject(:out) { inline(code, strategy: :aggressive, config: config) }

    let(:config) do
      Docscribe::Config.new('emit' => {
                              'include_default_message' => false,
                              'include_param_documentation' => false
                            })
    end

    let(:code) do
      <<~RUBY
        class Demo
          def greet(name)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'omits method documentation placeholder', :aggregate_failures do
      expect(out).not_to include('Method documentation.')
      expect(out).to include('# @param [Object] name')
      expect(out).not_to include('Param documentation.')
    end
  end

  describe 'aggressive mode with no_boilerplate — keeps existing descriptions' do
    subject(:out) { inline(code, strategy: :aggressive, config: config) }

    let(:config) do
      Docscribe::Config.new(
        'keep_descriptions' => true,
        'emit' => {
          'include_default_message' => false,
          'include_param_documentation' => false
        }
      )
    end

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [Object] name User full name
          # @return [String] greeting message
          def greet(name)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'preserves descriptions and omits boilerplate', :aggregate_failures do
      expect(out).to include('User full name')
      expect(out).not_to include('Method documentation.')
      expect(out).not_to include('Param documentation.')
    end
  end

  describe 'via CLI with -AB' do
    subject(:result) { Open3.capture3('ruby', exe, '-AB', path, chdir: dir) }

    let(:exe)  { File.expand_path('exe/docscribe') }
    let(:dir)  { Dir.mktmpdir }
    let(:path) { File.join(dir, 'foo.rb') }
    let(:content) { File.read(path) }

    before do
      File.write(path, <<~RUBY)
        class Foo
          def bar(name)
            "hi, \#{name}"
          end
        end
      RUBY
    end

    after { FileUtils.remove_entry(dir) }

    it 'generates tags without boilerplate text', :aggregate_failures do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      expect(result[2].exitstatus).to eq(0)
      expect(content).to include('# @param [Object] name')
      expect(content).not_to include('Method documentation.', 'Param documentation.')
    end
  end

  describe 'via CLI with -AkB' do
    subject(:result) { Open3.capture3('ruby', exe, '-AkB', path, chdir: dir) }

    let(:exe)  { File.expand_path('exe/docscribe') }
    let(:dir)  { Dir.mktmpdir }
    let(:path) { File.join(dir, 'foo.rb') }
    let(:content) { File.read(path) }

    before do
      File.write(path, <<~RUBY)
        class Foo
          # Docs
          #
          # @param [Object] name User name
          # @return [String] result
          def bar(name)
            "hi, \#{name}"
          end
        end
      RUBY
    end

    after { FileUtils.remove_entry(dir) }

    it 'combines -A -k -B: keeps descriptions, no boilerplate', :aggregate_failures do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      expect(result[2].exitstatus).to eq(0)
      expect(content).to include('User name')
      expect(content).not_to include('Method documentation.', 'Param documentation.')
    end
  end
end
