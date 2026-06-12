# frozen_string_literal: true

RSpec.describe Docscribe do
  subject(:out) { inline(code, file: 'spec_debug.rb') }

  let(:code) do
    <<~RUBY
      class A
        def foo(x); x; end
      end
    RUBY
  end

  describe 'when DOCSCRIBE_DEBUG=1' do
    let(:old) { ENV.fetch('DOCSCRIBE_DEBUG', nil) }

    before do
      ENV['DOCSCRIBE_DEBUG'] = '1'
      allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')
    end

    after { ENV['DOCSCRIBE_DEBUG'] = old }

    it 'prints a warning to stderr' do
      expect { out }.to output(/Docscribe DEBUG: DocBuilder\.build failed at spec_debug\.rb:/).to_stderr
    end
  end

  describe 'by default' do
    let(:old) { ENV.fetch('DOCSCRIBE_DEBUG', nil) }

    before do
      skip 'cannot suppress RBS fallback warning on Ruby 2.7' if RUBY_VERSION < '3.0'
      ENV['DOCSCRIBE_DEBUG'] = nil
      allow(Docscribe::Infer).to receive(:returns_spec_from_node).and_raise(StandardError, 'boom')
    end

    after { ENV['DOCSCRIBE_DEBUG'] = old }

    it 'does not print warnings to stderr' do
      expect { out }.not_to output.to_stderr
    end
  end
end
