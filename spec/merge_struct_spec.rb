# frozen_string_literal: true

RSpec.describe 'safe strategy struct docs' do
  it 'appends missing @!attribute blocks into an existing doc-like block for Struct.new assignment' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      # @todo docs
      # @!attribute [rw] a
      # @return [Object]
      # @param value [Object]
      Foo = Struct.new(:a, :b, keyword_init: true)
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe, config: conf)

    expect(out).to include('# @todo docs')
    expect(out).to include('# @!attribute [rw] a')
    expect(out).to include('# @!attribute [rw] b')
    expect(out.scan(/^\s*#\s*@!attribute\b/).size).to eq(2)
  end

  it 'inserts full struct docs when there is no doc-like block' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      # NOTE: keep this
      Foo = Struct.new(:name, keyword_init: true)
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe, config: conf)

    expect(out).to include('# NOTE: keep this')
    expect(out).to include('# @!attribute [rw] name')
  end

  it 'does not rewrite class-based struct style into assignment style' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class Foo < Struct.new(:a, :b, keyword_init: true)
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe, config: conf)

    expect(out).to include('class Foo < Struct.new(:a, :b, keyword_init: true)')
    expect(out).not_to include('Foo = Struct.new')
  end
end
