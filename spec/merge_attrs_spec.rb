# frozen_string_literal: true

RSpec.describe '--merge attrs' do
  it 'appends missing @!attribute blocks into an existing doc-like block' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        # @todo docs
        # @!attribute [r] a
        #   @return [Object]
        attr_reader :a, :b
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)

    expect(out).to include('# @todo docs')
    expect(out).to include('# @!attribute [r] a')
    expect(out).to include('# @!attribute [r] b')
    expect(out.scan(/^\s*#\s*@!attribute\b/).size).to eq(2)
  end

  it 'inserts full attr docs when there is no doc-like block (even if a normal comment exists)' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        # NOTE: keep this
        attr_reader :name
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)

    expect(out).to include('# NOTE: keep this')
    expect(out).to include('# @!attribute [r] name')
  end
end
