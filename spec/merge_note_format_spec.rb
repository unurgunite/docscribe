# frozen_string_literal: true

RSpec.describe '--merge formatting' do
  it 'merges into an existing doc-like block without introducing extra blank lines' do
    code = <<~RUBY
      module M
        module_function

        # @todo keep this
        # @return [String] already documented
        def foo(x)
          "ok"
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Existing lines preserved
    expect(out).to include('# @todo keep this')
    expect(out).to include('# @return [String] already documented')

    # Merge added note + param
    expect(out).to include('# @note module_function:')
    expect(out).to include('# @param [Object] x')

    # Ensure no empty line between @note and @param
    expect(out).to match(/@note module_function:.*\n\s*# @param/m)
    expect(out).not_to match(/@note module_function:.*\n\s*\n\s*# @param/m)
  end
end
