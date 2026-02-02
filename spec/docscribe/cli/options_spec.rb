# frozen_string_literal: true

require 'docscribe/cli/options'

RSpec.describe Docscribe::CLI::Options do
  it 'routes /regex/ passed to --include into method filters (not file filters)' do
    argv = %w[--dry --include /^A#foo$/ lib]
    opts = described_class.parse!(argv)

    expect(opts[:include]).to eq(['/^A#foo$/'])
    expect(opts[:include_file]).to eq([])
  end

  it 'routes /regex/ passed to --exclude into method filters (not file filters)' do
    argv = %w[--dry --exclude /^A#foo$/ lib]
    opts = described_class.parse!(argv)

    expect(opts[:exclude]).to eq(['/^A#foo$/'])
    expect(opts[:exclude_file]).to eq([])
  end
end

