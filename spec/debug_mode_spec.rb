# frozen_string_literal: true

RSpec.describe 'DOCSCRIBE_DEBUG' do
  it 'prints a warning to stderr when DOCSCRIBE_DEBUG=1 and doc building raises' do
    old = ENV.fetch('DOCSCRIBE_DEBUG', nil)
    ENV['DOCSCRIBE_DEBUG'] = '1'

    # Force an exception inside DocBuilder by breaking returns inference
    allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')

    code = <<~RUBY
      class A
        def foo(x); x; end
      end
    RUBY

    expect do
      # file: makes the debug output more meaningful
      Docscribe::InlineRewriter.insert_comments(code, file: 'spec_debug.rb')
    end.to output(/Docscribe DEBUG: DocBuilder\.build failed at spec_debug\.rb:/).to_stderr
  ensure
    ENV['DOCSCRIBE_DEBUG'] = old
  end

  it 'does not print warnings by default when doc building raises' do
    old = ENV.fetch('DOCSCRIBE_DEBUG', nil)
    ENV['DOCSCRIBE_DEBUG'] = nil

    allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')

    code = <<~RUBY
      class A
        def foo(x); x; end
      end
    RUBY

    expect do
      Docscribe::InlineRewriter.insert_comments(code, file: 'spec_debug.rb')
    end.not_to output.to_stderr
  ensure
    ENV['DOCSCRIBE_DEBUG'] = old
  end
end
