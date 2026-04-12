# frozen_string_literal: true

require 'docscribe/types/rbs/collection_loader'

RSpec.describe Docscribe::Types::RBS::CollectionLoader do
  describe '.resolve' do
    let(:root) { Dir.mktmpdir }

    after { FileUtils.rm_rf(root) }

    def write_lock(path: nil)
      data = { 'sources' => [], 'gems' => [] }
      data['path'] = path if path
      File.write(File.join(root, 'rbs_collection.lock.yaml'), data.to_yaml)
    end

    def create_collection_dir(rel)
      dir = File.join(root, rel)
      FileUtils.mkdir_p(dir)
      dir
    end

    context 'when rbs_collection.lock.yaml is absent' do
      it 'returns nil' do
        expect(described_class.resolve(root: root)).to be_nil
      end
    end

    context 'when lock-file is present but collection not installed' do
      it 'returns nil when default path does not exist' do
        write_lock
        expect(described_class.resolve(root: root)).to be_nil
      end

      it 'returns nil when custom path does not exist' do
        write_lock(path: 'vendor/rbs')
        expect(described_class.resolve(root: root)).to be_nil
      end
    end

    context 'when lock-file has no explicit path' do
      it 'falls back to .gem_rbs_collection when directory exists' do
        write_lock
        expected = create_collection_dir('.gem_rbs_collection')
        expect(described_class.resolve(root: root)).to eq(Pathname(expected).expand_path.to_s)
      end
    end

    context 'when lock-file has explicit custom path' do
      it 'returns the custom path when directory exists' do
        write_lock(path: 'vendor/rbs')
        expected = create_collection_dir('vendor/rbs')
        expect(described_class.resolve(root: root)).to eq(Pathname(expected).expand_path.to_s)
      end
    end
  end
end
