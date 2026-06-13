# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI::Run do
  subject(:result) { Open3.capture3('ruby', exe, *args, chdir: dir) }

  let(:exe)      { File.expand_path('exe/docscribe') }
  let(:dir)      { Dir.mktmpdir }
  let(:code) do
    <<~RUBY
      class Foo
        def greet(name)
          "Hello, \#{name}"
        end

        def bar(x, y)
          x + y
        end
      end
    RUBY
  end

  before { File.write("#{dir}/foo.rb", code) }
  after  { FileUtils.remove_entry(dir) }

  shared_examples 'correct exit status' do
    it 'exits 1 in check mode when updates needed' do
      expect(result[2].exitstatus).to eq(1)
    end
  end

  describe 'check mode (default)' do
    let(:args) { ['foo.rb'] }

    it 'prints progress markers to stdout' do
      expect(result[0]).to include('F')
    end

    it 'prints Would update to stdout' do
      expect(result[0]).to match(/^Would update:/)
    end

    it 'does not print Would update to stderr' do
      expect(result[1]).not_to match(/Would update/)
    end

    it 'prints explanations before summary' do
      output = result[0]
      fail_idx = output.index('Would update:')
      status_idx = output.index('Docscribe:')
      expect(fail_idx).to be < status_idx
    end

    it 'prints change reasons' do
      expect(result[0]).to include('missing docs for Foo#bar')
    end

    it 'prints all change reasons' do
      expect(result[0]).to include('missing docs for Foo#greet')
    end

    it 'prints summary line' do
      expect(result[0]).to match(/Docscribe: (FAILED|OK)/)
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --verbose' do
    let(:args) { %w[--verbose foo.rb] }

    it 'prints FAIL verdict per file' do
      expect(result[0]).to include('FAIL foo.rb')
    end

    it 'includes change reasons inline with verdict' do
      expect(result[0]).to match(/FAIL foo\.rb\n\s+- missing/)
    end

    it 'prints Would update without duplicating explanations' do
      output = result[0]
      after_would = output.split('Would update:').last || ''
      expect(after_would).not_to include('missing docs')
    end

    it 'prints summary line' do
      expect(result[0]).to match(/Docscribe: (FAILED|OK)/)
    end

    it 'does not output to stderr' do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      expect(result[1]).to be_empty
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --explain' do
    let(:args) { %w[--explain foo.rb] }

    it 'prints change reasons in summary (same as default)' do
      expect(result[0]).to include('missing docs for Foo#bar')
    end

    it 'prints Would update before summary' do
      output = result[0]
      fail_idx = output.index('Would update:')
      status_idx = output.index('Docscribe:')
      expect(fail_idx).to be < status_idx
    end

    it_behaves_like 'correct exit status'
  end

  describe 'write mode' do
    let(:args) { %w[-a foo.rb] }

    it 'prints C marker per file' do
      expect(result[0]).to include('C')
    end

    it 'prints update summary' do
      expect(result[0]).to match(/updated \d+ file/)
    end

    it 'outputs nothing to stderr' do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      expect(result[1]).to be_empty
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end

    it 'actually writes docs to file' do
      Open3.capture3('ruby', exe, '-a', 'foo.rb', chdir: dir)
      content = File.read("#{dir}/foo.rb")
      expect(content).to include('@param [Object] name')
    end
  end

  describe 'write mode with --verbose' do
    let(:args) { %w[-a --verbose foo.rb] }

    it 'prints CHANGED verdict with explanations' do
      expect(result[0]).to match(/CHANGED foo\.rb\n\s+- missing/)
    end

    it 'prints update summary' do
      expect(result[0]).to match(/updated \d+ file/)
    end
  end

  context 'when all files are fine' do
    let(:code) { <<~RUBY }
      # documentation
      class Foo; end
    RUBY

    let(:args) { ['foo.rb'] }

    it 'prints dot marker' do
      expect(result[0]).to start_with('.')
    end

    it 'prints OK summary' do
      expect(result[0]).to match(/Docscribe: OK/)
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end
  end
end
