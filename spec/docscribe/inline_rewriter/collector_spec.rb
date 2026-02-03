# frozen_string_literal: true

require 'docscribe/inline_rewriter/collector'

RSpec.describe Docscribe::InlineRewriter::Collector do
  it 'treats `private def foo` as private' do
    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })
    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end

  it 'treats `private def foo` as private (emits @private when enabled)' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end
end
