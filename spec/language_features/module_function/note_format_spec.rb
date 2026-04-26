# frozen_string_literal: true

RSpec.describe 'module_function note formatting' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      module M
        module_function
        def foo(x)
          x
        end
      end
    RUBY
  end

  it 'does not insert an extra blank line between @note and @param' do
    # Must have note
    expect(out).to include('# @note module_function:')

    # Note should be immediately followed by a tag line (no empty line in between).
    expect(out).to match(/@note module_function:.*\n\s*# @param/m)
    expect(out).not_to match(/@note module_function:.*\n\s*\n\s*# @param/m)
  end
end
