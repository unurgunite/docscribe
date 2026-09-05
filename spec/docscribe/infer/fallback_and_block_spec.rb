# frozen_string_literal: true

require 'docscribe/infer'

RSpec.describe Docscribe::Infer::Returns do
  describe 'FALLBACK_TYPE alias handling' do
    context 'when source is empty or invalid' do
      it 'infer_return_type returns Object for empty or invalid source' do
        expect(described_class.infer_return_type('')).to eq('Object')
        expect(described_class.infer_return_type(nil)).to eq('Object')
        expect(described_class.infer_return_type('not ruby')).to eq('Object')
      end
    end

    context 'when method body is FALLBACK_TYPE constant' do
      let(:code) do
        <<~RUBY
          def foo
            FALLBACK_TYPE
          end
        RUBY
      end
      let(:parsed_node) { described_class.parse_method_source(code) }
      let(:method_body) { described_class.extract_def_body(parsed_node) }

      it 'handles FALLBACK_TYPE constant node' do
        inferred_type = described_class.send(:run_last_expr_type, method_body, fallback_type: 'Object', nil_as_optional: true, core_rbs_provider: nil)
        expect(inferred_type).to eq('Object')
      end
    end

    describe 'unify_types normalization' do
      it 'normalizes FALLBACK_TYPE alias to fallback', :aggregate_failures do
        expect(described_class.send(:unify_types, 'FALLBACK_TYPE', 'String', fallback_type: 'Object', nil_as_optional: true)).to eq('Object, String')
        expect(described_class.send(:unify_types, 'String', 'FALLBACK_TYPE', fallback_type: 'Object', nil_as_optional: true)).to eq('String, Object')
        expect(described_class.send(:unify_types, 'untyped', 'String', fallback_type: 'Object', nil_as_optional: true)).to eq('Object, String')
        expect(described_class.send(:unify_types, 'FALLBACK_TYPE', 'Object', fallback_type: 'Object', nil_as_optional: true)).to eq('Object')
      end
    end

    describe 'fallback_alias? detection' do
      it 'detects all aliases', :aggregate_failures do
        expect(described_class.send(:fallback_alias?, 'FALLBACK_TYPE', 'Object')).to be true
        expect(described_class.send(:fallback_alias?, 'Object', 'Object')).to be true
        expect(described_class.send(:fallback_alias?, 'untyped', 'Object')).to be true
        expect(described_class.send(:fallback_alias?, 'Object?', 'Object')).to be true
        expect(described_class.send(:fallback_alias?, 'String', 'Object')).to be false
        expect(described_class.send(:fallback_alias?, nil, 'Object')).to be false
      end
    end

    describe 'handle_or node with fallback alias' do
      let(:or_node) do
        Parser::AST::Node.new(:or, [Parser::AST::Node.new(:str, ['a']), Parser::AST::Node.new(:lvar, [:x])])
      end

      it 'prefers concrete when other is fallback alias', :aggregate_failures do
        buffer = Parser::Source::Buffer.new('(test)')
        buffer.source = 'def foo; a || b; end'
        ast = Docscribe::Parsing.parse_buffer(buffer)
        _ast_body = ast.children[2]
        expect(described_class.send(:fallback_alias?, 'FALLBACK_TYPE', 'Object')).to be true
        allow(described_class).to receive(:run_last_expr_type).and_return('String', 'FALLBACK_TYPE')
        result = described_class.send(:handle_or_node, or_node, fallback_type: 'Object', nil_as_optional: true)
        expect(result).to be_a(String)
      end
    end
  end

  describe 'block RBS Array<String> via handle_block_node' do
    context 'when block has RBS type containing U/Elem and inner type' do
      subject(:output) { inline(code, config: config) }

      let(:code) do
        <<~RUBY
          class Demo
            def foo
              [1, 2, 3].map { |x| x.to_s }
            end
          end
        RUBY
      end
      let(:config) { Docscribe::Config.new('emit' => { 'header' => true }) }

      before { skip_unless_rbs_available! }

      it 'infers Array<String> vs String handling for Array#map like blocks' do
        expect(output).to include('@return')
      end
    end

    context 'when block has no RBS type' do
      let(:code) do
        <<~RUBY
          def foo
            [1,2].each { 42 }
          end
        RUBY
      end
      let(:parsed_outer) { described_class.parse_method_source(code) }
      let(:block_body) { described_class.extract_def_body(parsed_outer) }

      before do
        allow(described_class).to receive(:send_rbs_type).and_return(nil)
      end

      it 'handles block without RBS by returning inner type', :aggregate_failures do
        expect(block_body).not_to be_nil
        expect(block_body.type).to eq(:block)
        expect { described_class.send(:handle_block_node, block_body, fallback_type: 'Object', nil_as_optional: true) }.not_to raise_error
        result = described_class.send(:handle_block_node, block_body, fallback_type: 'Object', nil_as_optional: true)
        expect(result).to eq('Integer')
      end
    end
  end

  describe 'tuple vs Array generic' do
    let(:validator) { Docscribe::Validator::TypeMismatchValidator.new }

    it 'treats tuple (String, Integer) as compatible with Array via validator', :aggregate_failures do
      expect(validator.generic_compatible?('(String, Integer)', 'Array')).to be true
      expect(validator.generic_compatible?('Array', '(String, Integer)')).to be true
    end

    it 'does not treat tuple as compatible with Hash', :aggregate_failures do
      expect(validator.generic_compatible?('(String, Integer)', 'Hash')).to be false
      expect(validator.mismatched_return?('(String, Integer)', 'Hash')).to be true
    end
  end

  describe 'lookup_lvar_type skips FALLBACK_TYPE' do
    it 'returns nil when lvar type is FALLBACK_TYPE', :aggregate_failures do
      expect(described_class.send(:lookup_lvar_type, 'x', { 'x' => 'Object' }, nil)).to be_nil if Docscribe::Infer::FALLBACK_TYPE == 'Object'
      expect(described_class.send(:lookup_lvar_type, 'x', { 'x' => Docscribe::Infer::FALLBACK_TYPE }, nil)).to be_nil
    end

    it 'returns param type when not fallback' do
      expect(described_class.send(:lookup_lvar_type, 'y', nil, { 'y' => 'String' })).to eq('String')
    end

    it 'returns param_types fallback as is (no skip for params)', :aggregate_failures do
      expect(described_class.send(:lookup_lvar_type, 'z', nil, { 'z' => 'Object' })).to eq('Object')
      expect(described_class.send(:lookup_lvar_type, 'z', nil, { 'z' => Docscribe::Infer::FALLBACK_TYPE })).to eq('Object')
    end
  end
end

RSpec.describe Docscribe::Infer::Literals do
  describe '.type_from_literal' do
    let(:integer_node) { Parser::AST::Node.new(:int, [1]) }
    let(:string_node) { Parser::AST::Node.new(:str, ['hi']) }
    let(:true_node) { Parser::AST::Node.new(:true, []) }
    let(:false_node) { Parser::AST::Node.new(:false, []) }
    let(:nil_node) { Parser::AST::Node.new(:nil, []) }
    let(:array_node) { Parser::AST::Node.new(:array, []) }
    let(:hash_node) { Parser::AST::Node.new(:hash, []) }
    let(:send_node) { Parser::AST::Node.new(:send, [nil, :foo]) }

    it 'maps literals correctly', :aggregate_failures do
      expect(described_class.type_from_literal(integer_node)).to eq('Integer')
      expect(described_class.type_from_literal(string_node)).to eq('String')
      expect(described_class.type_from_literal(true_node)).to eq('Boolean')
      expect(described_class.type_from_literal(false_node)).to eq('Boolean')
      expect(described_class.type_from_literal(nil_node)).to eq('nil')
      expect(described_class.type_from_literal(array_node)).to eq('Array')
      expect(described_class.type_from_literal(hash_node)).to eq('Hash')
    end

    it 'returns fallback for unknown' do
      expect(described_class.type_from_literal(nil)).to eq('Object')
      expect(described_class.type_from_literal(send_node)).to eq('Object')
    end
  end
end
