# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'docscribe/inline_rewriter'
require 'docscribe/config'
require 'docscribe/cli/formatters'

RSpec.describe 'source field propagation (442)' do
  describe Docscribe::InlineRewriter do
    let(:config_validate) { Docscribe::Config.new('validate_types' => true) }
    let(:config_no_validate) { Docscribe::Config.new('validate_types' => false) }

    context 'when YARD return type is invalid syntax' do
      subject(:rewrite_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @return [Sym bol]
            def bar
              :x
            end
          end
        RUBY
      end

      it 'reports source syntax for invalid YARD', :aggregate_failures do
        expect(rewrite_result[:changes].size).to eq(1)
        change = rewrite_result[:changes].first
        expect(change[:type]).to eq(:invalid_type)
        expect(change[:source]).to eq('syntax')
        expect(change[:message]).to include('Sym bol')
      end
    end

    context 'when YARD return type mismatches inferred type without RBS' do
      subject(:rewrite_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'reports source infer for YARD mismatch', :aggregate_failures do
        expect(rewrite_result[:changes].size).to eq(1)
        expect(rewrite_result[:changes].first[:source]).to eq('infer')
        expect(rewrite_result[:changes].first[:type]).to eq(:updated_return)
      end
    end

    context 'when external RBS signature differs from YARD' do
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end
      let(:rbs_content) { "class Foo\n  def bar: () -> String\nend\n" }

      before { skip_unless_rbs_available! }

      it 'reports source rbs when external_sig differs', :aggregate_failures do
        Dir.mktmpdir do |tmp_dir|
          sig_dir = File.join(tmp_dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'foo.rbs'), rbs_content)
          config = Docscribe::Config.new('validate_types' => true, 'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          result = described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
          expect(result[:changes].first[:source]).to eq('rbs')
          expect(result[:changes].first[:type]).to eq(:updated_return)
        end
      end
    end

    context 'when YARD param type is invalid syntax' do
      subject(:rewrite_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_no_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @param [Sym bol] x
            # @return [Symbol]
            def bar(x = :sym)
              x
            end
          end
        RUBY
      end

      it 'reports source syntax for param invalid', :aggregate_failures do
        param_change = rewrite_result[:changes].find { |change| change[:type] == :invalid_type }
        expect(param_change).not_to be_nil
        expect(param_change[:source]).to eq('syntax')
      end
    end

    context 'when YARD param type mismatches inferred default' do
      subject(:rewrite_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @param [String] x
            # @return [Object]
            def bar(x: 123)
              x
            end
          end
        RUBY
      end

      it 'reports source infer for param mismatch', :aggregate_failures do
        param_change = rewrite_result[:changes].find { |change| change[:type] == :updated_param }
        expect(param_change).not_to be_nil
        expect(param_change[:source]).to eq('infer')
        expect(param_change[:param]).to eq('x')
      end
    end

    context 'when RBS provides param type differing from YARD' do
      let(:code) do
        <<~RUBY
          class Foo
            # @param [String] x
            # @return [Object]
            def bar(x)
              x
            end
          end
        RUBY
      end
      let(:rbs_content) { "class Foo\n  def bar: (Integer x) -> Object\nend\n" }

      before { skip_unless_rbs_available! }

      it 'reports source rbs for param mismatch' do
        Dir.mktmpdir do |tmp_dir|
          sig_dir = File.join(tmp_dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'foo.rbs'), rbs_content)
          config = Docscribe::Config.new('validate_types' => true, 'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          result = described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
          param_change = result[:changes].find { |change| change[:type] == :updated_param }
          expect(param_change).not_to be_nil
          expect(param_change[:source]).to eq('rbs')
        end
      end
    end

    context 'when no validation and no invalid syntax' do
      subject(:rewrite_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_no_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'does not report source' do
        expect(rewrite_result[:changes].any? { |change| change[:type] == :updated_return }).to be false
      end
    end

    context 'when comparing safe and aggressive strategies' do
      subject(:safe_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: config_validate, file: 'test.rb')
      end

      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end
      let(:aggressive_result) do
        described_class.rewrite_with_report(code, strategy: :aggressive, config: config_validate, file: 'test.rb')
      end

      it 'preserves source in safe mode and generates corrected output in aggressive', :aggregate_failures do
        expect(safe_result[:changes].first[:source]).to eq('infer')
        expect(safe_result[:changes].first[:type]).to eq(:updated_return)
        expect(aggressive_result[:output]).to include('@return [String]')
      end
    end
  end

  describe 'formatters source propagation' do
    let(:formatter_json) { Docscribe::CLI::Formatters::Json.new }
    let(:state_without_source) do
      {
        changed: false, had_errors: false, checked_ok: 0, checked_fail: 1,
        corrected: 0, corrected_paths: [], corrected_changes: {},
        fail_paths: ['test.rb'],
        fail_changes: { 'test.rb' => [{ type: :missing_return, line: 5, method: 'Foo#bar', message: 'msg' }] },
        error_paths: [], error_messages: {},
        type_mismatch_paths: [], type_mismatch_changes: {}
      }
    end
    let(:check_options) { { verbose: false, quiet: false, explain: false, mode: :check } }
    let(:sarif_options) { { verbose: false, quiet: false, explain: false, mode: :check, format: :sarif } }
    let(:formatter_sarif) { Docscribe::CLI::Formatters::Sarif.new }

    def json_offense_for(source)
      build_json_state_with_source(source)
    end

    def sarif_result_for(source)
      build_sarif_state_with_source(source)
    end

    def build_json_state_with_source(source)
      state = {
        changed: false, had_errors: false, checked_ok: 0, checked_fail: 1,
        corrected: 0, corrected_paths: [], corrected_changes: {},
        fail_paths: ['test.rb'],
        fail_changes: { 'test.rb' => [{ type: :updated_return, line: 5, method: 'Foo#bar', source: source, message: 'msg' }] },
        error_paths: [], error_messages: {},
        type_mismatch_paths: [], type_mismatch_changes: {}
      }
      options = { verbose: false, quiet: false, explain: false, mode: :check }
      parsed = JSON.parse(capture_stdout { formatter_json.format_check_summary(state: state, options: options) })
      parsed['files'][0]['offenses'][0]
    end

    def build_sarif_state_with_source(source)
      state = {
        changed: false, had_errors: false, checked_ok: 0, checked_fail: 1,
        corrected: 0, corrected_paths: [], corrected_changes: {},
        fail_paths: ['test.rb'],
        fail_changes: { 'test.rb' => [{ type: :updated_return, line: 5, method: 'Foo#bar', source: source, message: 'msg' }] },
        error_paths: [], error_messages: {},
        type_mismatch_paths: [], type_mismatch_changes: {}
      }
      options = { verbose: false, quiet: false, explain: false, mode: :check, format: :sarif }
      parsed = JSON.parse(capture_stdout { formatter_sarif.format_check_summary(state: state, options: options) })
      parsed['runs'][0]['results'][0]
    end

    it 'JSON includes source when provided - syntax', :aggregate_failures do
      offense = json_offense_for('syntax')
      expect(offense['source']).to eq('syntax')
    end

    it 'JSON includes source rbs', :aggregate_failures do
      expect(json_offense_for('rbs')['source']).to eq('rbs')
    end

    it 'JSON includes source infer', :aggregate_failures do
      expect(json_offense_for('infer')['source']).to eq('infer')
    end

    it 'JSON omits source when not provided' do
      json = JSON.parse(capture_stdout { formatter_json.format_check_summary(state: state_without_source, options: check_options) })
      expect(json['files'][0]['offenses'][0]).not_to have_key('source')
    end

    it 'SARIF includes source in properties - syntax', :aggregate_failures do
      result = sarif_result_for('syntax')
      expect(result['properties']['source']).to eq('syntax')
    end

    it 'SARIF includes source rbs', :aggregate_failures do
      expect(sarif_result_for('rbs')['properties']['source']).to eq('rbs')
    end

    it 'SARIF includes source infer', :aggregate_failures do
      expect(sarif_result_for('infer')['properties']['source']).to eq('infer')
    end

    it 'SARIF omits properties when no source' do
      json = JSON.parse(capture_stdout { formatter_sarif.format_check_summary(state: state_without_source, options: sarif_options) })
      result = json['runs'][0]['results'][0]
      expect(result).not_to have_key('properties')
    end

    context 'when change type is invalid_type' do
      let(:invalid_state) do
        {
          changed: false, had_errors: false, checked_ok: 0, checked_fail: 1,
          corrected: 0, corrected_paths: [], corrected_changes: {},
          fail_paths: ['test.rb'],
          fail_changes: { 'test.rb' => [{ type: :invalid_type, line: 5, method: 'Foo#bar', source: 'syntax', message: 'invalid' }] },
          error_paths: [], error_messages: {},
          type_mismatch_paths: [], type_mismatch_changes: {}
        }
      end

      it 'JSON maps invalid_type to warning and Docscribe/InvalidType', :aggregate_failures do
        json = JSON.parse(capture_stdout { formatter_json.format_check_summary(state: invalid_state, options: check_options) })
        offense = json['files'][0]['offenses'][0]
        expect(offense['severity']).to eq('warning')
        expect(offense['cop_name']).to eq('Docscribe/InvalidType')
        expect(offense['source']).to eq('syntax')
      end

      it 'SARIF maps invalid_type to warning and Docscribe/InvalidType', :aggregate_failures do
        json = JSON.parse(capture_stdout { formatter_sarif.format_check_summary(state: invalid_state, options: sarif_options) })
        result = json['runs'][0]['results'][0]
        expect(result['level']).to eq('warning')
        expect(result['ruleId']).to eq('Docscribe/InvalidType')
        expect(result['properties']['source']).to eq('syntax')
      end
    end
  end

  describe 'daemon propagation via handle_check/run_rewrite' do
    let(:ruby_source_with_infer_mismatch) do
      <<~RUBY
        class Foo
          # @return [Integer]
          def bar
            "hello"
          end
        end
      RUBY
    end

    let(:daemon_cli_overrides) do
      { 'validate_types' => true, 'include' => [], 'exclude' => [], 'include_file' => [], 'exclude_file' => [], 'sig_dirs' => [], 'rbi_dirs' => [], 'no_boilerplate' => true }
    end

    it 'daemon check returns changes with stringified source', :aggregate_failures do
      require 'docscribe/server'
      Dir.mktmpdir do |tmp_dir|
        file = File.join(tmp_dir, 'test.rb')
        File.write(file, ruby_source_with_infer_mismatch)
        socket_path = File.join(tmp_dir, 'daemon.sock')
        daemon = Docscribe::Server::Daemon.new(socket_path: socket_path, idle_timeout: 60)
        daemon.send(:load_dependencies)
        daemon.send(:apply_cli_overrides, daemon_cli_overrides)
        _source, result = daemon.send(:rewrite_file, file, :safe)
        change = result[:changes].find { |entry| entry[:type] == :updated_return }
        expect(change).not_to be_nil
        expect(change[:source]).to eq('infer')
        rewrite = daemon.send(:run_rewrite, file, :safe)
        stringified_change = rewrite['changes'].find { |entry| entry['type'].to_s == 'updated_return' }
        expect(stringified_change).not_to be_nil
        expect(stringified_change['source']).to eq('infer')
      end
    end

    it 'daemon handles check_batch with source propagation', :aggregate_failures do
      require 'docscribe/server'
      Dir.mktmpdir do |tmp_dir|
        first_file = File.join(tmp_dir, 'a.rb')
        second_file = File.join(tmp_dir, 'b.rb')
        File.write(first_file, "class A\n# @return [Integer]\ndef foo\n\"hi\"\nend\nend\n")
        File.write(second_file, "class B\n# @return [Sym bol]\ndef bar\n:x\nend\nend\n")
        socket_path = File.join(tmp_dir, 'daemon2.sock')
        daemon = Docscribe::Server::Daemon.new(socket_path: socket_path, idle_timeout: 60)
        daemon.send(:load_dependencies)
        daemon.send(:apply_cli_overrides, daemon_cli_overrides)
        first_result = daemon.send(:run_rewrite, first_file, :safe)
        second_result = daemon.send(:run_rewrite, second_file, :safe)
        expect(first_result['changes'].find { |entry| %w[updated_return invalid_type].include?(entry['type'].to_s) }['source']).to eq('infer')
        expect(second_result['changes'].find { |entry| entry['type'].to_s == 'invalid_type' }['source']).to eq('syntax')
      end
    end
  end
end
