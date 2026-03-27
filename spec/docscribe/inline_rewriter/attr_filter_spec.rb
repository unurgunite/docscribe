# frozen_string_literal: true

RSpec.describe 'attr_* + filter' do
  it 'does not emit @!attribute when all implied methods are excluded' do
    conf = Docscribe::Config.new(
      'emit' => { 'attributes' => true },
      'filter' => { 'exclude' => ['A#name', 'A#name='] }
    )

    code = <<~RUBY
      class A
        attr_accessor :name
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).not_to include('@!attribute')
  end
end
