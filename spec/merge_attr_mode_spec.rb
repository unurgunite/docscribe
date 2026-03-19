# frozen_string_literal: true

RSpec.describe '--merge mode (attrs)' do
  it 'appends missing @!attribute blocks for undocumented attr names' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        # @!attribute [r] a
        #   @return [Object]
        attr_reader :a, :b
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)

    expect(out).to include('# @!attribute [r] a')
    expect(out).to include('# @!attribute [r] b') # added
  end

  it 'inserts full attr docs if there is no doc-like block (even if a normal comment exists)' do
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

  it 'treats @todo blocks as doc-like and merges into them' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        # @todo Document this properly
        attr_reader :name
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)
    expect(out).to include('# @todo Document this properly')
    expect(out).to include('# @!attribute [r] name')
  end
end
