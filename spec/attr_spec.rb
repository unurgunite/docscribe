# frozen_string_literal: true

RSpec.describe 'attr_* documentation' do
  def inline(code, config:)
    Docscribe::InlineRewriter.insert_comments(code, config: config)
  end

  it 'generates @!attribute docs for attr_reader when enabled' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        attr_reader :name
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [r] name')
    expect(out).to include('#   @return [Object]')
  end

  it 'generates @!attribute docs for attr_accessor (rw) when enabled' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        attr_accessor :name
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [rw] name')
    expect(out).to include('#   @return [Object]')
    expect(out).to include('#   @param value [Object]')
  end

  it 'adds @private for private attr_reader when emit.visibility_tags is enabled' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true, 'visibility_tags' => true })

    code = <<~RUBY
      class A
        private
        attr_reader :secret
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [r] secret')
    expect(out).to include('# @private')
  end
end
