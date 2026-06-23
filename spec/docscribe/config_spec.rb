# frozen_string_literal: true

RSpec.describe Docscribe::Config do
  describe '#process_method?' do
    describe 'falls back to DEFAULT filter scopes/visibilities when filter keys are missing' do
      subject(:conf) { described_class.new }

      it { expect(conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)).to be(true) }
      it { expect(conf.process_method?(container: 'A', scope: :class, visibility: :private, name: :bar)).to be(true) }
    end

    describe 'excludes matching methods even if included by scope/visibility' do
      subject(:conf) { described_class.new('filter' => { 'exclude' => ['*#initialize'] }) }

      it do
        expect(conf.process_method?(container: 'A', scope: :instance, visibility: :public,
                                    name: :initialize)).to be(false)
      end
    end

    describe 'when include is non-empty, only included methods pass' do
      subject(:conf) { described_class.new('filter' => { 'include' => ['A#foo'] }) }

      it { expect(conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)).to be(true) }

      it do
        expect(conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :bar)).to be(false)
      end
    end

    describe 'respects visibilities allow-list' do
      subject(:conf) { described_class.new('filter' => { 'visibilities' => ['public'] }) }

      it { expect(conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)).to be(true) }

      it do
        expect(conf.process_method?(container: 'A', scope: :instance, visibility: :private, name: :foo)).to be(false)
      end
    end
  end
end
