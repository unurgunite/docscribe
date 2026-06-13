# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Docscribe::InlineRewriter do
  describe 'aggressive mode (default)' do
    subject(:out) { inline(code, strategy: :aggressive) }

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [Object] name User full name
          # @param [Object] age Age in years
          # @return [String] greeting message
          def greet(name, age)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'replaces param descriptions with static placeholder', :aggregate_failures do
      expect(out).to include(param_tag('name', 'Object'))
      expect(out).not_to include('User full name')
    end

    it 'replaces return tag with no description' do
      expect(out).to include('# @return [String]')
    end
  end

  describe 'aggressive mode with keep_descriptions: true' do
    subject(:out) { inline(code, strategy: :aggressive, config: config) }

    let(:config) { Docscribe::Config.new('keep_descriptions' => true) }

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [Object] name User full name
          # @param [Object] age Age in years
          # @return [String] greeting message
          def greet(name, age)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'preserves existing @param descriptions', :aggregate_failures do
      expect(out).to include('User full name')
      expect(out).to include('Age in years')
    end

    it 'preserves existing @return description' do
      expect(out).to include('# @return [String] greeting message')
    end

    it 'does not duplicate param lines' do
      count = out.scan(/@param/).length
      expect(count).to eq(2)
    end
  end

  describe 'aggressive mode with keep_descriptions: true — partial' do
    subject(:out) { inline(code, strategy: :aggressive, config: config) }

    let(:config) { Docscribe::Config.new('keep_descriptions' => true) }

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [Object] name
          # @param [Object] age
          def greet(name, age)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'inserts static placeholder when no description exists', :aggregate_failures do
      expect(out).to include(param_tag('name', 'Object'))
      expect(out).to include(param_tag('age', 'Object'))
    end
  end

  describe 'safe mode unaffected by keep_descriptions' do
    subject(:out) { inline(code, strategy: :safe, config: config) }

    let(:config) { Docscribe::Config.new('keep_descriptions' => true) }

    let(:code) do
      <<~RUBY
        class Demo
          # Existing doc
          #
          # @param [Object] name User full name
          def greet(name, age)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'preserves existing param descriptions' do
      expect(out).to include('User full name')
    end

    it 'appends placeholder for new params' do
      expect(out).to include(param_tag('age', 'Object'))
    end
  end

  describe 'aggressive mode keep_descriptions: true — @return only' do
    subject(:out) { inline(code, strategy: :aggressive, config: config) }

    let(:config) { Docscribe::Config.new('keep_descriptions' => true) }

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @return [String] the formatted output
          def greet(name)
            "Hello, \#{name}"
          end
        end
      RUBY
    end

    it 'preserves @return description and generates @param', :aggregate_failures do
      expect(out).to include('# @return [String] the formatted output')
      expect(out).to include(param_tag('name', 'Object'))
    end
  end

  describe 'via CLI' do
    subject(:result) { Open3.capture3('ruby', exe, '-Ak', path, chdir: dir) }

    let(:exe)  { File.expand_path('exe/docscribe') }
    let(:dir)  { Dir.mktmpdir }
    let(:path) { File.join(dir, 'foo.rb') }

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

    it 'preserves descriptions with -Ak', :aggregate_failures do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      expect(result[2].exitstatus).to eq(0)
      content = File.read(path)
      expect(content).to include('User name')
      expect(content).to include('# @return [String] result')
    end
  end
end
