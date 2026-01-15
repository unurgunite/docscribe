# frozen_string_literal: true

RSpec.describe Docscribe::Parsing do
  it 'parses Ruby 3.4+ syntax with the prism backend' do
    skip 'Ruby < 3.4' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4')

    code = <<~RUBY
      [1,2,3].map { it + 1 }
    RUBY

    ast = described_class.parse(code, backend: :prism)
    expect(ast).not_to be_nil
  end
end
