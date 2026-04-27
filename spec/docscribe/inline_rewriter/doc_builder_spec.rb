# frozen_string_literal: true

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

    it 'omits the default method message when doc.include_default_message is false' do
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

    it 'omits param placeholder text when doc.include_param_documentation is false' do
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

    it 'omits both method and param placeholder text when both flags are false' do
      expect(out).not_to include('Method documentation.')
      expect(out).not_to include('Param documentation.')
      expect(out).to include('# @param [Object] foo')
    end
  end
end
