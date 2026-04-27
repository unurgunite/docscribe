# frozen_string_literal: true

RSpec.describe 'attr_* documentation' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  let(:code) { <<~RUBY }
    class A
      attr_reader :name
    end
  RUBY

  it 'generates @!attribute docs for attr_reader when enabled' do
    expect(out).to include('# @!attribute [r] name')
    expect(out).to include('#   @return [Object]')
  end

  describe 'attr_accessor' do
    let(:code) { <<~RUBY }
      class A
        attr_accessor :name
      end
    RUBY

    it 'generates @!attribute docs for attr_accessor (rw) when enabled' do
      expect(out).to include('# @!attribute [rw] name')
      expect(out).to include('#   @return [Object]')
      expect(out).to include(param_tag('value', 'Object', space_size: 3, struct: true).to_s)
    end
  end

  describe 'private attr_reader' do
    let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true, 'visibility_tags' => true }) }

    let(:code) { <<~RUBY }
      class A
        private
        attr_reader :secret
      end
    RUBY

    it 'adds @private for private attr_reader when emit.visibility_tags is enabled' do
      expect(out).to include('# @!attribute [r] secret')
      expect(out).to include('# @private')
    end
  end
end
