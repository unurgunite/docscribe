RSpec.describe 'Inline rewriter respects existing tags' do
  it 'does not insert when user provided @param/@option above the method' do
    code = <<~RUBY
      class A
      # @param [String] name The name
      def foo(name); "x"; end
      end
    RUBY

    out = inline(code)
    expect(out).not_to include('# +A#foo+')
    expect(out).to include('@param [String] name The name') # original stays
  end

  it 'does not insert when user provided @return' do
    code = <<~RUBY
      class A
      # @return [String] pre-documented
      def bar; "x"; end
      end
    RUBY

    out = inline(code)
    expect(out).not_to include('# +A#bar+')
    expect(out).to include('@return [String] pre-documented')
  end
end
