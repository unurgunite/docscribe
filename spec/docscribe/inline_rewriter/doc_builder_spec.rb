# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/inline_rewriter/doc_builder'

RSpec.describe Docscribe::InlineRewriter::DocBuilder do
  subject(:out) { inline(code) }

  let(:code) { <<~RUBY }
    class A
      def foo(x = 1); x; end
    end
  RUBY

  it 'infers types for positional optional args (optarg) without crashing' do
    expect(out).to include(param_tag('x', 'Integer'))
  end

  describe 'include_default_message is false' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'include_default_message' => false }) }

    let(:code) { <<~RUBY }
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    it 'omits the default method message when doc.include_default_message is false', :aggregate_failures do
      expect(out).not_to include('Method documentation.')
      expect(out).to include('# @param [Object] foo Param documentation.')
    end
  end

  describe 'include_param_documentation is false' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'include_param_documentation' => false }) }

    let(:code) { <<~RUBY }
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    it 'omits param placeholder text when doc.include_param_documentation is false', :aggregate_failures do
      expect(out).to include('# @param [Object] foo')
      expect(out).not_to include('Param documentation.')
    end
  end

  describe 'both flags are false' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'include_default_message' => false, 'include_param_documentation' => false }) }

    let(:code) { <<~RUBY }
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    it 'omits both method and param placeholder text when both flags are false', :aggregate_failures do
      expect(out).not_to include('Method documentation.')
      expect(out).not_to include('Param documentation.')
      expect(out).to include('# @param [Object] foo')
    end
  end

  describe '.join_multiline_tags' do
    subject(:joined) { described_class.join_multiline_tags(lines) }

    context 'with single-line @param (brackets already balanced)' do
      let(:lines) do
        [
          '# @param [String] name The name.',
          '# @return [String]'
        ]
      end

      it { is_expected.to eq(lines) }
    end

    context 'with multiline @param where type spans two lines' do
      let(:lines) do
        [
          '# @param [Hash<Symbol, Object>, Insertion,',
          '#   AttrInsertion] ins',
          '# @return [Integer]'
        ]
      end

      it 'joins into a single line', :aggregate_failures do
        expect(joined.length).to eq(2)
        expect(joined[0]).to match(/# @param \[Hash<Symbol, Object>, Insertion,\s+AttrInsertion\] ins/)
        expect(joined[1]).to eq('# @return [Integer]')
      end
    end

    context 'with multiline @param and triple-space indent on continuation' do
      let(:lines) do
        [
          '# @param [Hash<Symbol, Object>, Docscribe::InlineRewriter::Collector::Insertion,',
          '#   Docscribe::InlineRewriter::Collector::AttrInsertion] ins',
          '# @return [Integer]'
        ]
      end

      it 'joins into a single line', :aggregate_failures do
        expect(joined.length).to eq(2)
        expect(joined[0]).to include('AttrInsertion] ins')
        expect(joined[1]).to eq('# @return [Integer]')
      end
    end

    context 'with multiline @return' do
      let(:lines) do
        [
          '# @return [Array<Symbol,',
          '#   Integer>]'
        ]
      end

      it 'joins into a single line', :aggregate_failures do
        expect(joined.length).to eq(1)
        expect(joined[0]).to match(/# @return \[Array<Symbol,\s+Integer>\]/)
      end
    end

    context 'with single-line @return' do
      let(:lines) { ['# @return [String]'] }

      it { is_expected.to eq(lines) }
    end
  end

  describe '.parse_existing_doc_tags' do
    subject(:info) { described_class.parse_existing_doc_tags(lines) }

    context 'with multiline @param type' do
      let(:lines) do
        [
          '# @param [Hash<Symbol, Object>, Insertion,',
          '#   AttrInsertion] ins'
        ]
      end

      it 'extracts the param name' do
        expect(info[:param_names]).to include('ins')
      end

      it 'extracts the param type' do
        expect(info[:param_types]).to include('ins' => a_string_including('Hash<Symbol, Object>'))
      end
    end

    context 'with single-line @param' do
      let(:lines) do
        [
          '# @param [Symbol] kind',
          '# @param [String] name'
        ]
      end

      it 'extracts all param names' do
        expect(info[:param_names]).to include('kind', 'name')
      end
    end
  end

  describe 'integration: safe mode with multiline @param' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) { Docscribe::Config.new('emit' => { 'params' => true, 'return' => true }) }

    let(:code) { <<~RUBY }
      class Demo
        # Documentation
        #
        # @param [Hash<Symbol, Object>, Insertion,
        #   AttrInsertion] ins
        # @return [Integer]
        def plugin_insertion_pos(kind, ins)
          ins
        end
      end
    RUBY

    it 'preserves the multiline @param lines', :aggregate_failures do
      expect(out).to include('# @param [Hash<Symbol, Object>, Insertion,')
      expect(out).to include('#   AttrInsertion] ins')
    end

    it 'adds only missing params (kind), not existing ones (ins)', :aggregate_failures do
      expect(out).to include('# @param [Object] kind')
      expect(out).not_to include('# @param [Object] ins')
    end

    it 'preserves @return' do
      expect(out).to include('# @return [Integer]')
    end
  end

  describe 'integration: safe mode adds missing param alongside multiline existing one' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) { Docscribe::Config.new('emit' => { 'params' => true, 'return' => false }) }

    let(:code) { <<~RUBY }
      class Demo
        # Documentation
        #
        # @param [Hash<Symbol, Object>, Insertion,
        #   AttrInsertion] ins
        def plugin_insertion_pos(kind, ins)
          ins
        end
      end
    RUBY

    it 'has exactly one @param tag entry (multiline ins + new kind)' do
      expect(out.scan(/^\s*# @param/).size).to eq(2)
    end
  end

  describe 'does not duplicate conditional rescue @return in aggressive keep_descriptions mode' do
    subject(:out) { inline(code, config: config, strategy: :aggressive) }

    let(:config) { Docscribe::Config.new('keep_descriptions' => true, 'emit' => { 'rescue_conditional_returns' => true }) }

    let(:code) { <<~RUBY }
      class A
        # @return [Integer] if RuntimeError
        def foo
          1
        rescue RuntimeError
          0
        end
      end
    RUBY

    it 'does not duplicate conditional @return [Integer] if RuntimeError' do
      expect(out.scan(/^(\s*# @return \[Integer\] if RuntimeError\s*$)/).size).to eq(1)
    end
  end

  describe 'rescue body returning a parameter with known type' do
    subject(:out) { inline(code, config: conf, strategy: :aggressive) }

    let(:conf) { Docscribe::Config.new('emit' => { 'rescue_conditional_returns' => true }) }

    let(:code) { <<~RUBY }
      class A
        def count_lines(text = '')
          text.lines.size
        rescue StandardError
          text
        end
      end
    RUBY

    it 'uses String, not Object, for rescue @return (param type from default)' do
      expect(out).to include('# @return [String] if StandardError')
    end
  end

  describe 'explicit receiver call in rescue resolved via signature_provider', :rbs do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def fallback: -> String
        end

        class Foo
          def bar: (Demo demo) -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Foo
          def bar(demo)
            "ok"
          rescue StandardError
            demo.fallback
          end
        end
      RUBY
    end

    it 'resolves rescue return type from explicit receiver call via RBS' do
      expect(out).to include('# @return [String] if StandardError')
    end
  end
end
