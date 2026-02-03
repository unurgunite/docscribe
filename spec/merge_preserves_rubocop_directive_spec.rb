# frozen_string_literal: true

RSpec.describe '--merge preserves rubocop directives' do
  it 'keeps rubocop:disable lines and merges tags into the same doc block' do
    code = <<~RUBY
      class A
        # rubocop:disable Metrics/AbcSize
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# rubocop:disable Metrics/AbcSize')
    expect(out).to include('# @todo docs')
    expect(out).to include('# @param [Object] x')
  end
end
