# frozen_string_literal: true

RSpec.describe 'DOCSCRIBE_DEBUG' do
  subject(:out) { inline(code, file: 'spec_debug.rb') }

  let(:code) do
    <<~RUBY
      class A
        def foo(x); x; end
      end
    RUBY
  end

  it 'prints a warning to stderr when DOCSCRIBE_DEBUG=1 and doc building raises' do
    old = ENV.fetch('DOCSCRIBE_DEBUG', nil)
    ENV['DOCSCRIBE_DEBUG'] = '1'

    # Force an exception inside DocBuilder by breaking returns inference
    allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')

    expect do
      # file: makes the debug output more meaningful
      out
    end.to output(/Docscribe DEBUG: DocBuilder\.build failed at spec_debug\.rb:/).to_stderr
  ensure
    ENV['DOCSCRIBE_DEBUG'] = old
  end

  it 'does not print warnings by default when doc building raises' do
    old = ENV.fetch('DOCSCRIBE_DEBUG', nil)
    ENV['DOCSCRIBE_DEBUG'] = nil

    allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')

    expect do
      out
    end.not_to output.to_stderr
  ensure
    ENV['DOCSCRIBE_DEBUG'] = old
  end
end
