# frozen_string_literal: true

RSpec.describe Docscribe::Parsing do
  subject(:ast) { described_class.parse(code, backend: :prism) }

  let(:nodes) { %i[block itblock] }
  let(:code) do
    <<~RUBY
      [1,2,3].map { it + 1 }
    RUBY
  end
  let(:send_node) do
    if %i[block itblock].include?(ast.type)
      ast.children[0]
    else
      ast
    end
  end

  before do
    skip 'Ruby < 3.4' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4')
  end

  it { expect(ast).to be_a(Parser::AST::Node) }
  it { expect(nodes).to include(ast.type) }
  it { expect(send_node).to be_a(Parser::AST::Node) }
  it { expect(send_node.type).to eq(:send) }
end
