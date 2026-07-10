# frozen_string_literal: true

require 'docscribe/cli/run'

RSpec.describe Docscribe::CLI::Run do
  describe '#fetch_work' do
    it 'pops the first path from array under mutex' do
      paths = %w[a b c]
      result = described_class.fetch_work(paths, Mutex.new)
      expect(result).to eq('a')
    end

    it 'removes popped path from array' do
      paths = %w[a b c]
      described_class.fetch_work(paths, Mutex.new)
      expect(paths).to eq(%w[b c])
    end

    it 'returns nil when paths is empty' do
      expect(described_class.fetch_work([], Mutex.new)).to be_nil
    end
  end

  describe '#initial_run_state' do
    it 'returns a hash with changed false' do
      expect(described_class.send(:initial_run_state)[:changed]).to be(false)
    end

    it 'returns a hash with checked_ok zero' do
      expect(described_class.send(:initial_run_state)[:checked_ok]).to be(0)
    end

    it 'returns a hash with empty fail_paths' do
      expect(described_class.send(:initial_run_state)[:fail_paths]).to be_empty
    end

    it 'returns a hash with empty fail_changes' do
      expect(described_class.send(:initial_run_state)[:fail_changes]).to be_empty
    end

    it 'provides deep copy isolation' do
      state = described_class.send(:initial_run_state)
      state[:fail_paths] << 'x'
      other = described_class.send(:initial_run_state)
      expect(other[:fail_paths]).to be_empty
    end
  end

  describe '#merge_state_flags' do
    it 'sets changed when source has changed' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state).tap { |s| s[:changed] = true }
      described_class.merge_state_flags(target, source)
      expect(target[:changed]).to be(true)
    end

    it 'sets had_errors when source has errors' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state).tap { |s| s[:had_errors] = true }
      described_class.merge_state_flags(target, source)
      expect(target[:had_errors]).to be(true)
    end

    it 'does not override already set flags' do
      target = described_class.send(:initial_run_state).tap { |t| t[:changed] = true }
      source = described_class.send(:initial_run_state)
      described_class.merge_state_flags(target, source)
      expect(target[:changed]).to be(true)
    end
  end

  describe '#merge_state_counts' do
    it 'sums all counters from source into target' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state)
      source.merge!(checked_ok: 3, checked_fail: 2, corrected: 1, processed: 10)
      described_class.merge_state_counts(target, source)
      expect(target[:checked_ok]).to eq(3)
    end

    it 'sums checked_fail counter' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state).tap { |s| s[:checked_fail] = 2 }
      described_class.merge_state_counts(target, source)
      expect(target[:checked_fail]).to eq(2)
    end

    it 'sums corrected counter' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state).tap { |s| s[:corrected] = 1 }
      described_class.merge_state_counts(target, source)
      expect(target[:corrected]).to eq(1)
    end

    it 'sums processed counter' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state).tap { |s| s[:processed] = 10 }
      described_class.merge_state_counts(target, source)
      expect(target[:processed]).to eq(10)
    end

    it 'accumulates across multiple merges' do
      target = described_class.send(:initial_run_state)
      described_class.merge_state_counts(target, described_class.send(:initial_run_state).tap { |s| s[:checked_ok] = 1 })
      described_class.merge_state_counts(target, described_class.send(:initial_run_state).tap { |s| s[:checked_ok] = 2 })
      expect(target[:checked_ok]).to eq(3)
    end
  end

  describe '#merge_state_arrays' do
    it 'concatenates fail_paths arrays' do
      target = described_class.send(:initial_run_state).tap { |t| t[:fail_paths] = ['a.rb'] }
      source = described_class.send(:initial_run_state).tap { |s| s[:fail_paths] = ['b.rb'] }
      described_class.merge_state_arrays(target, source)
      expect(target[:fail_paths]).to eq(%w[a.rb b.rb])
    end

    it 'concatenates corrected_paths' do
      target = described_class.send(:initial_run_state).tap { |t| t[:corrected_paths] = ['c.rb'] }
      source = described_class.send(:initial_run_state).tap { |s| s[:corrected_paths] = ['d.rb'] }
      described_class.merge_state_arrays(target, source)
      expect(target[:corrected_paths]).to eq(%w[c.rb d.rb])
    end
  end

  describe '#merge_state_hashes' do
    it 'merges fail_changes from source into target' do
      target = described_class.send(:initial_run_state)
      source = described_class.send(:initial_run_state)
      source[:fail_changes]['a.rb'] = [{ type: :missing_return }]
      described_class.merge_state_hashes(target, source)
      expect(target[:fail_changes]['a.rb']).to eq([{ type: :missing_return }])
    end

    it 'overwrites existing error_messages key' do
      target = described_class.send(:initial_run_state).tap { |t| t[:error_messages]['a.rb'] = 'old error' }
      source = described_class.send(:initial_run_state).tap { |s| s[:error_messages]['a.rb'] = 'new error' }
      described_class.merge_state_hashes(target, source)
      expect(target[:error_messages]['a.rb']).to eq('new error')
    end
  end

  describe '#handle_worker_error' do
    it 'sets had_errors to true' do
      state = described_class.send(:initial_run_state)
      described_class.handle_worker_error(StandardError.new('err'), 'bad.rb', state, Mutex.new)
      expect(state[:had_errors]).to be(true)
    end

    it 'records path in error_paths' do
      state = described_class.send(:initial_run_state)
      described_class.handle_worker_error(StandardError.new('err'), 'bad.rb', state, Mutex.new)
      expect(state[:error_paths]).to eq(['bad.rb'])
    end

    it 'records error class and message' do
      state = described_class.send(:initial_run_state)
      described_class.handle_worker_error(StandardError.new('test error'), 'bad.rb', state, Mutex.new)
      expect(state[:error_messages]['bad.rb']).to include('StandardError: test error')
    end
  end

  describe '#run_exit_code' do
    let(:opts) { { mode: :check } }

    it 'returns 2 when had_errors' do
      state = described_class.send(:initial_run_state).tap { |s| s[:had_errors] = true }
      expect(described_class.send(:run_exit_code, opts, state)).to eq(2)
    end

    it 'returns 1 when check mode and changed' do
      state = described_class.send(:initial_run_state).tap { |s| s[:changed] = true }
      expect(described_class.send(:run_exit_code, opts, state)).to eq(1)
    end

    it 'returns 0 on success' do
      state = described_class.send(:initial_run_state)
      expect(described_class.send(:run_exit_code, opts, state)).to eq(0)
    end
  end
end
