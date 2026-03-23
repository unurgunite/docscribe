# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter::SourceHelpers do
  def find_first_def(node)
    return node if node.is_a?(Parser::AST::Node) && %i[def defs].include?(node.type)
    return nil unless node.is_a?(Parser::AST::Node)

    node.children.each do |child|
      found = find_first_def(child)
      return found if found
    end

    nil
  end

  it 'includes all contiguous doc lines above a method, including trailing @note lines' do
    code = <<~RUBY
      module M
        # @param [Object] x Param documentation.
        # @return [Object]
        # @note module_function: when included, also defines #foo (instance visibility: private)
        def foo(x); x; end
      end
    RUBY

    buffer = Parser::Source::Buffer.new('(example)', source: code)
    ast = Docscribe::Parsing.parse_buffer(buffer)
    node = find_first_def(ast)

    expect(node).not_to be_nil

    bol = described_class.line_start_range(buffer, node)
    info = described_class.doc_comment_block_info(buffer, bol.begin_pos)

    expect(info).not_to be_nil
    expect(info[:doc_lines].join).to include('@note module_function:')
  end
end
