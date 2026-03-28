# frozen_string_literal: true

RSpec.describe 'Struct.new documentation' do
  it 'generates @!attribute docs for constant-assigned Struct.new' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      Foo = Struct.new(:a, :b, keyword_init: true)
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [rw] a')
    expect(out).to include('# @!attribute [rw] b')
    expect(out).to include('#   @return [Object]')
    expect(out).to include(param_tag('value', 'Object', space_size: 3, struct: true).to_s)
    expect(out).to include('Foo = Struct.new(:a, :b, keyword_init: true)')
  end

  it 'generates @!attribute docs for class Foo < Struct.new(...)' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class Foo < Struct.new(:a, :b, keyword_init: true)
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [rw] a')
    expect(out).to include('# @!attribute [rw] b')
    expect(out).to include('class Foo < Struct.new(:a, :b, keyword_init: true)')
  end

  it 'supports named-first Struct.new style' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      Foo = Struct.new("Foo", :a, :b, keyword_init: true)
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @!attribute [rw] a')
    expect(out).to include('# @!attribute [rw] b')
    expect(out).not_to include('# @!attribute [rw] Foo')
  end
end
