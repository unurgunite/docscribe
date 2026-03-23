# frozen_string_literal: true

require 'docscribe/cli/options'

RSpec.describe Docscribe::CLI::Options do
  it 'routes /regex/ passed to --include into method filters (not file filters)' do
    argv = %w[--include /^A#foo$/ lib]
    opts = described_class.parse!(argv)

    expect(opts[:include]).to eq(['/^A#foo$/'])
    expect(opts[:include_file]).to eq([])
  end

  it 'routes /regex/ passed to --exclude into method filters (not file filters)' do
    argv = %w[--exclude /^A#foo$/ lib]
    opts = described_class.parse!(argv)

    expect(opts[:exclude]).to eq(['/^A#foo$/'])
    expect(opts[:exclude_file]).to eq([])
  end

  it 'uses inspect-safe mode by default' do
    opts = described_class.parse!(%w[lib])

    expect(opts[:mode]).to eq(:check)
    expect(opts[:strategy]).to eq(:safe)
  end

  it 'uses safe write mode for -a' do
    opts = described_class.parse!(%w[-a lib])

    expect(opts[:mode]).to eq(:write)
    expect(opts[:strategy]).to eq(:safe)
  end

  it 'uses aggressive write mode for -A' do
    opts = described_class.parse!(%w[-A lib])

    expect(opts[:mode]).to eq(:write)
    expect(opts[:strategy]).to eq(:aggressive)
  end

  it 'uses stdin mode with safe strategy by default' do
    opts = described_class.parse!(%w[--stdin])

    expect(opts[:mode]).to eq(:stdin)
    expect(opts[:strategy]).to eq(:safe)
  end

  it 'uses stdin mode with aggressive strategy for -A --stdin' do
    opts = described_class.parse!(%w[-A --stdin])

    expect(opts[:mode]).to eq(:stdin)
    expect(opts[:strategy]).to eq(:aggressive)
  end

  it 'enables Sorbet with --sorbet' do
    opts = described_class.parse!(%w[--sorbet lib])

    expect(opts[:sorbet]).to eq(true)
    expect(opts[:rbi_dirs]).to eq([])
  end

  it 'adds RBI dirs and implies Sorbet with --rbi-dir' do
    opts = described_class.parse!(%w[--rbi-dir sorbet/rbi --rbi-dir rbi lib])

    expect(opts[:sorbet]).to eq(true)
    expect(opts[:rbi_dirs]).to eq(%w[sorbet/rbi rbi])
  end
end
