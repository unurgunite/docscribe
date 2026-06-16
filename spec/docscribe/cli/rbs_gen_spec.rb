# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/cli/rbs_gen'

RSpec.describe Docscribe::CLI::RbsGen do
  def capture_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = orig
  end

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = orig
  end

  describe '.run' do
    it 'shows error when no files found' do
      err = capture_stderr { expect(described_class.run(%w[--dry-run nonexistent.rb])).to eq(2) }
      expect(err).to include('No files found')
    end

    it 'generates RBS for a file with YARD docs' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          # @param [String] name
          # @return [Integer]
          def process(name)
            name.length
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def process: (String name) -> Integer')
      end
    end

    it 'generates RBS for file without YARD docs' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          def foo
            :bar
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def foo: () -> untyped')
      end
    end

    it 'handles class methods via self.' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          class Foo
            # @return [String]
            def self.bar
              'bar'
            end
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def self.bar: () -> String')
      end
    end

    it 'handles class << self' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          class Foo
            class << self
              # @return [String]
              def bar
                'bar'
              end
            end
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def self.bar: () -> String')
      end
    end

    it 'handles module_function' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          module Foo
            # @return [String]
            def bar
              'bar'
            end

            module_function :bar
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def bar: () -> String')
      end
    end

    it 'generates RBS for a directory' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.rb'), <<~RUBY)
          # @return [Integer]
          def a; 1; end
        RUBY
        File.write(File.join(dir, 'b.rb'), <<~RUBY)
          # @return [String]
          def b; 'b'; end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', dir])).to eq(0)
        end
        expect(out).to include('def a: () -> Integer')
        expect(out).to include('def b: () -> String')
      end
    end

    it 'converts YARD types to RBS' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          # @param [Array<String>] items
          # @param [Hash{Symbol => Integer}] counts
          # @param [Boolean] enabled
          # @return [Array<Integer>]
          def transform(items, counts, enabled)
            []
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def transform: (Array[String] items, Hash[Symbol, Integer] counts, bool enabled) -> Array[Integer]')
      end
    end

    it 'converts @option to keyword args' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          # @param [Hash] opts options hash
          # @option opts [Boolean] :verbose enable verbose
          # @option opts [String] :format output format
          # @return [void]
          def run(opts)
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('?bool verbose')
        expect(out).to include('?String format')
      end
    end

    it 'writes files when not in dry-run mode' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'foo.rb')
        File.write(rb, <<~RUBY)
          # @return [String]
          def foo
            'foo'
          end
        RUBY

        out = capture_stdout do
          expect(described_class.run(['-o', File.join(dir, 'sig'), rb])).to eq(0)
        end

        rbs_path = File.join(dir, 'sig', 'foo.rbs')
        expect(File).to exist(rbs_path)
        expect(File.read(rbs_path)).to include('def foo: () -> String')
        expect(out).to include("Generated #{rbs_path}")
      end
    end

    it 'skips existing files without --force' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          # @return [String]
          def foo; end
        RUBY

        rbs_path = File.join(dir, 'sig', 'test.rbs')
        FileUtils.mkdir_p(File.join(dir, 'sig'))
        File.write(rbs_path, 'old content')

        out = capture_stdout do
          err = capture_stderr do
            expect(described_class.run(['-o', File.join(dir, 'sig'), rb])).to eq(0)
          end
          expect(err).to include('Skipping')
        end
        expect(File.read(rbs_path)).to eq('old content')
      end
    end

    it 'overwrites with --force' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'test.rb')
        File.write(rb, <<~RUBY)
          # @return [String]
          def foo; end
        RUBY

        rbs_path = File.join(dir, 'sig', 'test.rbs')
        FileUtils.mkdir_p(File.join(dir, 'sig'))
        File.write(rbs_path, 'old content')

        out = capture_stdout do
          expect(described_class.run(['-o', File.join(dir, 'sig'), '-f', rb])).to eq(0)
        end
        expect(File.read(rbs_path)).to include('def foo: () -> String')
      end
    end

    it 'handles files gracefully' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'broken.rb')
        File.write(rb, 'def foo(')

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to include('def foo:')
      end
    end

    it 'handles empty file' do
      Dir.mktmpdir do |dir|
        rb = File.join(dir, 'empty.rb')
        File.write(rb, '')

        out = capture_stdout do
          expect(described_class.run(['-n', rb])).to eq(0)
        end
        expect(out).to be_empty
      end
    end
  end

  describe 'parse_yard_tags' do
    it 'parses @param [Type] name format' do
      tags = described_class.send(:parse_yard_tags, ['# @param [String] name the name'])
      expect(tags.params.size).to eq(1)
      expect(tags.params.first.name).to eq('name')
      expect(tags.params.first.type).to eq('String')
    end

    it 'parses @param name [Type] format' do
      tags = described_class.send(:parse_yard_tags, ['# @param name [String] the name'])
      expect(tags.params.size).to eq(1)
      expect(tags.params.first.name).to eq('name')
      expect(tags.params.first.type).to eq('String')
    end

    it 'parses @return' do
      tags = described_class.send(:parse_yard_tags, ['# @return [Integer] the count'])
      expect(tags.return_type).to eq('Integer')
    end

    it 'returns nil return_type when absent' do
      tags = described_class.send(:parse_yard_tags, ['# @param [String] name'])
      expect(tags.return_type).to be_nil
    end

    it 'parses @option' do
      tags = described_class.send(:parse_yard_tags, [
        '# @option options [Boolean] :verbose enable verbose'
      ])
      expect(tags.options.size).to eq(1)
      expect(tags.options.first.name).to eq('verbose')
      expect(tags.options.first.type).to eq('Boolean')
    end

    it 'strips leading colon from option name' do
      tags = described_class.send(:parse_yard_tags, [
        '# @option opts [String] :name the name'
      ])
      expect(tags.options.first.name).to eq('name')
    end
  end

  describe 'type_to_rbs' do
    it 'converts Array<String>' do
      expect(described_class.send(:type_to_rbs, 'Array<String>')).to eq('Array[String]')
    end

    it 'converts Boolean to bool' do
      expect(described_class.send(:type_to_rbs, 'Boolean')).to eq('bool')
    end

    it 'converts Hash{Symbol => Integer}' do
      expect(described_class.send(:type_to_rbs, 'Hash{Symbol => Integer}')).to eq('Hash[Symbol, Integer]')
    end

    it 'converts Object to untyped' do
      expect(described_class.send(:type_to_rbs, 'Object')).to eq('untyped')
    end
  end

  describe 'find_yard_block' do
    it 'finds the comment block before a method' do
      src_lines = [
        "# comment 1\n",
        "# comment 2\n",
        "def foo\n"
      ]
      comment_map = { 1 => '# comment 1', 2 => '# comment 2' }
      block = described_class.send(:find_yard_block, 3, comment_map, src_lines)
      expect(block).to eq(['# comment 1', '# comment 2'])
    end

    it 'returns empty when no comments before method' do
      src_lines = [
        "x = 1\n",
        "def foo\n"
      ]
      comment_map = {}
      block = described_class.send(:find_yard_block, 2, comment_map, src_lines)
      expect(block).to be_empty
    end

    it 'stops at blank lines' do
      src_lines = [
        "# comment\n",
        "\n",
        "def foo\n"
      ]
      comment_map = { 1 => '# comment' }
      block = described_class.send(:find_yard_block, 3, comment_map, src_lines)
      expect(block).to be_empty
    end
  end

  describe 'format_method_sig' do
    it 'formats instance method' do
      md = described_class::MethodDef.new(
        name: 'foo', scope: :instance, container: nil, file: 'x.rb', line: 1,
        yard_tags: described_class::YardTags.new(params: [], return_type: 'String', options: [])
      )
      expect(described_class.send(:format_method_sig, md)).to eq('def foo: () -> String')
    end

    it 'formats class method with self.' do
      md = described_class::MethodDef.new(
        name: 'bar', scope: :class, container: nil, file: 'x.rb', line: 1,
        yard_tags: described_class::YardTags.new(params: [], return_type: 'Integer', options: [])
      )
      expect(described_class.send(:format_method_sig, md)).to eq('def self.bar: () -> Integer')
    end

    it 'includes params' do
      md = described_class::MethodDef.new(
        name: 'process', scope: :instance, container: nil, file: 'x.rb', line: 1,
        yard_tags: described_class::YardTags.new(
          params: [described_class::ParamTag.new(name: 'name', type: 'String')],
          return_type: 'void',
          options: []
        )
      )
      expect(described_class.send(:format_method_sig, md)).to eq('def process: (String name) -> void')
    end

    it 'includes options as optional keyword args' do
      md = described_class::MethodDef.new(
        name: 'run', scope: :instance, container: nil, file: 'x.rb', line: 1,
        yard_tags: described_class::YardTags.new(
          params: [],
          return_type: 'void',
          options: [described_class::ParamTag.new(name: 'verbose', type: 'Boolean')]
        )
      )
      expect(described_class.send(:format_method_sig, md)).to eq('def run: (?bool verbose) -> void')
    end
  end

  describe 'build_rbs_content' do
    it 'groups methods by container' do
      m1 = described_class::MethodDef.new(name: 'foo', scope: :instance, container: 'Foo', file: 'x.rb', line: 1, yard_tags: nil)
      m2 = described_class::MethodDef.new(name: 'bar', scope: :instance, container: 'Foo', file: 'x.rb', line: 2, yard_tags: nil)
      m3 = described_class::MethodDef.new(name: 'baz', scope: :instance, container: nil, file: 'x.rb', line: 3, yard_tags: nil)

      content = described_class.send(:build_rbs_content, [m1, m2, m3])
      expect(content).to include('class Foo')
      expect(content).to include('  def foo: () -> untyped')
      expect(content).to include('  def bar: () -> untyped')
      expect(content).to include('end')
      expect(content).to include('def baz: () -> untyped')
    end
  end
end
