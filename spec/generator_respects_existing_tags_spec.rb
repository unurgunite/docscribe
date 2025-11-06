# frozen_string_literal: true

RSpec.describe 'Generator respects existing tags' do
  def generate(code)
    StingrayDocsInternal::Generator.generate_documentation(code)
  end

  it 'skips generating @param if user provided @param or @option' do
    code = <<~RUBY
      class A

      # @param [String] name The name

      def foo(name); "x"; end
      end
    RUBY

    out = generate(code)
    # Should not generate our default-object param doc
    expect(out).not_to include('@param [Object] name Param documentation.')
    # Still includes method header and source
    expect(out).to include('# +A#foo+')
    expect(out).to include('def foo(name); "x"; end')
  end

  it 'skips generating @return if user provided @return' do
    code = <<~RUBY
      class A

      # @return [String] pre-documented

      def bar; "x"; end
      end
    RUBY

    out = generate(code)
    expect(out).not_to match(/^\s*# @return \[/) # no auto @return
    expect(out).to include('# +A#bar+')
    expect(out).to include('def bar; "x"; end')
  end
end
