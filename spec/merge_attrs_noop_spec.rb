# frozen_string_literal: true

RSpec.describe '--merge attrs no-op' do
  it 'does nothing when all @!attribute blocks already exist' do
    conf = Docscribe::Config.new('emit' => { 'attributes' => true })

    code = <<~RUBY
      class A
        # @todo docs
        # @!attribute [r] a
        #   @return [Object]
        # @!attribute [r] b
        #   @return [Object]
        attr_reader :a, :b
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)
    expect(out).to eq(code)
  end
end
