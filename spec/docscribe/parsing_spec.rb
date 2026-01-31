# frozen_string_literal: true

RSpec.describe Docscribe::Parsing do
  subject(:nodes) { %i[block itblock] }

  it 'parses Ruby 3.4+ syntax with the prism backend and returns parser-gem AST nodes' do
    skip 'Ruby < 3.4' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4')

    code = <<~RUBY
      [1,2,3].map { it + 1 }
    RUBY

    ast = described_class.parse(code, backend: :prism)

    expect(ast).to be_a(Parser::AST::Node)
    expect(nodes).to include(ast.type)

    # Ensure we really parsed a method call, not just any node shape.
    send_node =
      if %i[block itblock].include?(ast.type)
        ast.children[0] # (:send) node
      else
        ast
      end

    expect(send_node).to be_a(Parser::AST::Node)
    expect(send_node.type).to eq(:send)
  end
end
