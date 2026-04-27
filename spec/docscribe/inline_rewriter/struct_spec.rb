# frozen_string_literal: true

RSpec.describe 'Struct.new documentation' do
  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  describe 'constant-assigned Struct.new' do
    subject(:out) { inline(code, config: conf) }

    let(:code) { <<~RUBY }
      Foo = Struct.new(:a, :b, keyword_init: true)
    RUBY

    it 'generates @!attribute docs for constant-assigned Struct.new' do
      expect(out).to include('# @!attribute [rw] a')
      expect(out).to include('# @!attribute [rw] b')
      expect(out).to include('#   @return [Object]')
      expect(out).to include(param_tag('value', 'Object', space_size: 3, struct: true).to_s)
      expect(out).to include('Foo = Struct.new(:a, :b, keyword_init: true)')
    end
  end

  describe 'class Foo < Struct.new' do
    subject(:out) { inline(code, config: conf) }

    let(:code) { <<~RUBY }
      class Foo < Struct.new(:a, :b, keyword_init: true)
      end
    RUBY

    it 'generates @!attribute docs for class Foo < Struct.new(...)' do
      expect(out).to include('# @!attribute [rw] a')
      expect(out).to include('# @!attribute [rw] b')
      expect(out).to include('class Foo < Struct.new(:a, :b, keyword_init: true)')
    end
  end

  describe 'named-first Struct.new style' do
    subject(:out) { inline(code, config: conf) }

    let(:code) { <<~RUBY }
      Foo = Struct.new("Foo", :a, :b, keyword_init: true)
    RUBY

    it 'supports named-first Struct.new style' do
      expect(out).to include('# @!attribute [rw] a')
      expect(out).to include('# @!attribute [rw] b')
      expect(out).not_to include('# @!attribute [rw] Foo')
    end
  end
end
