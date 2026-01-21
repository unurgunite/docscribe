# frozen_string_literal: true

RSpec.describe Docscribe::Config do
  describe '#process_method?' do
    it 'falls back to DEFAULT filter scopes/visibilities when filter keys are missing' do
      conf = described_class.new({}) # no filter provided at all

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)
      ).to be(true)

      expect(
        conf.process_method?(container: 'A', scope: :class, visibility: :private, name: :bar)
      ).to be(true)
    end

    it 'excludes matching methods even if included by scope/visibility' do
      conf = described_class.new(
        'filter' => { 'exclude' => ['*#initialize'] }
      )

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :initialize)
      ).to be(false)
    end

    it 'when include is non-empty, only included methods pass' do
      conf = described_class.new(
        'filter' => { 'include' => ['A#foo'] }
      )

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)
      ).to be(true)

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :bar)
      ).to be(false)
    end

    it 'respects visibilities allow-list' do
      conf = described_class.new(
        'filter' => { 'visibilities' => ['public'] }
      )

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :public, name: :foo)
      ).to be(true)

      expect(
        conf.process_method?(container: 'A', scope: :instance, visibility: :private, name: :foo)
      ).to be(false)
    end
  end
end
