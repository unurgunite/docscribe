# frozen_string_literal: true

RSpec.describe 'Inline rewriter filter' do
  def inline(code, filter_overrides)
    conf = Docscribe::Config.new('filter' => filter_overrides)
    Docscribe::InlineRewriter.insert_comments(code, config: conf)
  end

  it 'excludes initialize by glob pattern' do
    code = <<~RUBY
      class A
        def initialize; end
        def foo; 1; end
      end
    RUBY

    out = inline(code, { 'exclude' => ['*#initialize'] })
    expect(out).not_to include('+A#initialize+')
    expect(out).to include('+A#foo+')
  end

  it 'includes only matching methods when include is non-empty' do
    code = <<~RUBY
      class A
        def foo; 1; end
        def bar; 2; end
      end
    RUBY

    out = inline(code, { 'include' => ['A#foo'] })
    expect(out).to include('+A#foo+')
    expect(out).not_to include('+A#bar+')
  end
end
