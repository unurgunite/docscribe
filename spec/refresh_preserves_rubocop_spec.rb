# frozen_string_literal: true

RSpec.describe '--refresh preserves rubocop directives' do
  it 'preserves leading rubocop directives but replaces doc blocks' do
    code = <<~RUBY
      class A
        # rubocop:disable Metrics/AbcSize
        # old doc
        # @return [String]
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)

    expect(out).to include('# rubocop:disable Metrics/AbcSize')
    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# old doc')
    expect(out).not_to include('# @return [String]')
  end
end
