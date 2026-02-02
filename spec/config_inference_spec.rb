# frozen_string_literal: true

RSpec.describe 'Inference config' do
  it 'respects inference.fallback_type for unknown return types' do
    conf = Docscribe::Config.new('inference' => { 'fallback_type' => 'Any' })

    code = <<~RUBY
      class A
        def foo
          something_dynamic
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).to include('# +A#foo+ -> Any')
    expect(out).to include('# @return [Any]')
  end

  it 'respects inference.nil_as_optional=false (uses union instead of ?)' do
    conf = Docscribe::Config.new('inference' => { 'nil_as_optional' => false })

    code = <<~RUBY
      class A
        def foo(x)
          if x
            "a"
          else
            nil
          end
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).to include('# +A#foo+ -> String, nil')
    expect(out).to include('# @return [String, nil]')
  end

  it 'respects inference.treat_options_keyword_as_hash=false' do
    conf = Docscribe::Config.new('inference' => { 'treat_options_keyword_as_hash' => false })

    code = <<~RUBY
      class A
        def foo(options:)
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).to include('# @param [Object] options')
  end
end
