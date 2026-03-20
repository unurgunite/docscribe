# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter::SourceHelpers do
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
    node = ast.children.last.children.first # adjust if needed

    bol = described_class.line_start_range(buffer, node)
    info = described_class.doc_comment_block_info(buffer, bol.begin_pos)

    expect(info[:doc_lines].join).to include('@note module_function:')
  end
end
