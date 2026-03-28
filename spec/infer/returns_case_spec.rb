# frozen_string_literal: true

RSpec.describe 'return inference for case expressions' do
  it 'does not crash on methods whose body is a case expression' do
    code = <<~RUBY
      class A
        def foo(x)
          case x
          when 1 then 1
          else 2
          end
        end
      end
    RUBY

    out = inline(code)
    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
  end
end
