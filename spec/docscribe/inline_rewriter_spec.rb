# frozen_string_literal: true

require 'docscribe/inline_rewriter'

RSpec.describe Docscribe::InlineRewriter do
  it 'preserves tab indentation when inserting docs' do
    code = "class A\n\tdef foo; 1; end\nend\n"
    out = inline(code)
    expect(out).to include("\t# +A#foo+ -> Integer")
  end

  it 'uses line indentation for inline modifier defs (private def ...)' do
    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    out = inline(code)
    expect(out).to include('  # +A#foo+ -> Integer')
  end

  it 'does not duplicate existing @!attribute entries without access mode' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      # @!attribute node
      #   @return [Parser::AST::Node]
      # @!attribute scope
      #   @return [Symbol]
      AttrInsertion = Struct.new(:node, :scope)
    RUBY

    out = described_class.insert_comments(code, strategy: :safe, config: conf)

    expect(out.scan(/^\s*#\s*@!attribute\b/).size).to eq(2)
    expect(out).to include('# @!attribute node')
    expect(out).to include('# @!attribute scope')
    expect(out).not_to include('# @!attribute [rw] node')
    expect(out).not_to include('# @!attribute [rw] scope')
  end
end
