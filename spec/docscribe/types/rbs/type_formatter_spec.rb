# frozen_string_literal: true

RSpec.describe 'Docscribe::Types::RBS::TypeFormatter' do
  before do
    skip_unless_rbs_available!
    require 'docscribe/types/rbs/type_formatter'
  end

  describe '.to_yard' do
    def yard(type)
      Docscribe::Types::RBS::TypeFormatter.to_yard(type)
    end

    let(:integer_type) { RBS::Types::ClassInstance.new(name: type_name('::Integer'), args: [], location: nil) }
    let(:string_type) { RBS::Types::ClassInstance.new(name: type_name('::String'), args: [], location: nil) }

    it 'returns Object for nil' do
      expect(yard(nil)).to eq('Object')
    end

    describe 'base types' do
      it 'formats Any as Object' do
        expect(yard(RBS::Types::Bases::Any.new(location: nil))).to eq('Object')
      end

      it 'formats Bool as Boolean' do
        expect(yard(RBS::Types::Bases::Bool.new(location: nil))).to eq('Boolean')
      end

      it 'formats Void as void' do
        expect(yard(RBS::Types::Bases::Void.new(location: nil))).to eq('void')
      end

      it 'formats Nil as nil' do
        expect(yard(RBS::Types::Bases::Nil.new(location: nil))).to eq('nil')
      end

      it 'formats Top as Object' do
        expect(yard(RBS::Types::Bases::Top.new(location: nil))).to eq('Object')
      end

      it 'formats Bottom as Object' do
        expect(yard(RBS::Types::Bases::Bottom.new(location: nil))).to eq('Object')
      end

      it 'formats Self as self' do
        expect(yard(RBS::Types::Bases::Self.new(location: nil))).to eq('self')
      end

      it 'formats Instance as Object' do
        expect(yard(RBS::Types::Bases::Instance.new(location: nil))).to eq('Object')
      end

      it 'formats Class as Class' do
        expect(yard(RBS::Types::Bases::Class.new(location: nil))).to eq('Class')
      end
    end

    def type_name(str)
      RBS::TypeName.parse(str)
    end

    describe 'compound types' do
      it 'formats Optional' do
        type = RBS::Types::Optional.new(type: string_type, location: nil)
        expect(yard(type)).to eq('String?')
      end

      it 'formats Union' do
        type = RBS::Types::Union.new(types: [string_type, integer_type], location: nil)
        expect(yard(type)).to eq('String, Integer')
      end

      it 'formats Tuple' do
        type = RBS::Types::Tuple.new(types: [string_type, integer_type], location: nil)
        expect(yard(type)).to eq('(String, Integer)')
      end

      it 'formats Record' do
        type = RBS::Types::Record.new(
          fields: { name: string_type, age: integer_type },
          location: nil
        )
        expect(yard(type)).to eq('Hash<Symbol, String, Integer>')
      end

      it 'formats Intersection' do
        type = RBS::Types::Intersection.new(types: [string_type, integer_type], location: nil)
        expect(yard(type)).to eq('String & Integer')
      end

      it 'formats Variable' do
        type = RBS::Types::Variable.new(name: :Elem, location: nil)
        expect(yard(type)).to eq('Elem')
      end

      # rubocop:disable RSpec/ExampleLength
      it 'formats Proc' do
        type = RBS::Types::Proc.new(
          type: RBS::Types::Function.new(
            required_positionals: [],
            optional_positionals: [],
            rest_positionals: nil,
            trailing_positionals: [],
            required_keywords: {},
            optional_keywords: {},
            rest_keywords: nil,
            return_type: RBS::Types::Bases::Void.new(location: nil)
          ),
          block: nil,
          location: nil,
          self_type: nil
        )
        expect(yard(type)).to eq('Proc')
      end
      # rubocop:enable RSpec/ExampleLength

      it 'formats Literal' do
        type = RBS::Types::Literal.new(literal: 42, location: nil)
        expect(yard(type)).to eq('Integer')
      end
    end
  end
end
