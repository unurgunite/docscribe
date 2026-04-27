# frozen_string_literal: true

RSpec.describe 'return inference for case expressions' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class A
        def foo(x)
          case x
          when 1 then 1
          else 2
          end
        end
      end
    RUBY
  end

  it 'does not crash on methods whose body is a case expression' do
    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
  end
end
