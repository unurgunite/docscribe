# frozen_string_literal: true

require 'docscribe/validator/generic_compatibility'

RSpec.describe Docscribe::Validator::GenericCompatibility do
  subject(:mod) { described_class }

  describe '.compatible? dynamic checks (no hardcodes)' do
    context 'when generic base matches' do
      it 'treats Hash vs Hash<Symbol, String> as compatible' do
        expect(mod.compatible?('Hash', 'Hash<Symbol, String>')).to be true
      end

      it 'treats Array vs Array<String> as compatible' do
        expect(mod.compatible?('Array', 'Array<String>')).to be true
      end

      it 'detects mismatch when bases differ' do
        expect(mod.compatible?('Hash', 'Array<String>')).to be false
      end
    end

    context 'when short names equal (FQN vs short)' do
      it 'treats Parser::Source::Range vs Range as compatible' do
        expect(mod.compatible?('Parser::Source::Range', 'Range')).to be true
      end

      it 'treats Docscribe::Config vs Config as compatible' do
        expect(mod.compatible?('Docscribe::Config', 'Config')).to be true
      end

      it 'treats Result FQN vs Result as compatible' do
        expect(mod.compatible?('Docscribe::Validator::TypeMismatchValidator::Result', 'Result')).to be true
      end

      it 'detects mismatch when short differs' do
        expect(mod.compatible?('Docscribe::Config', 'String')).to be false
      end
    end

    context 'when alias hash with lowercase vs Hash' do
      it 'treats json_document vs Hash as compatible' do
        expect(mod.compatible?('Docscribe::CLI::Formatters::Json::json_document', 'Hash')).to be true
      end

      it 'treats custom alias my_alias vs Hash as compatible dynamically' do
        expect(mod.compatible?('Foo::Bar::my_custom_alias', 'Hash')).to be true
      end

      it 'does not treat Config (capital) vs Hash as compatible' do
        expect(mod.compatible?('Docscribe::Config', 'Hash')).to be false
      end
    end

    context 'when tuple vs Array' do
      it 'treats (String, Integer) vs Array as compatible' do
        expect(mod.compatible?('(String, Integer)', 'Array')).to be true
      end
    end

    context 'when optional vs nil' do
      it 'treats String? vs nil as compatible' do
        expect(mod.compatible?('String?', 'nil')).to be true
      end

      it 'treats String, nil vs nil as compatible' do
        expect(mod.compatible?('String, nil', 'nil')).to be true
      end

      it 'treats String vs nil as not compatible' do
        expect(mod.compatible?('String', 'nil')).to be false
      end
    end

    context 'when union containment' do
      it 'treats String vs String, Integer as compatible' do
        expect(mod.compatible?('String', 'String, Integer')).to be true
      end
    end

    context 'when optional suffix' do
      it 'treats String vs String? as compatible' do
        expect(mod.compatible?('String', 'String?')).to be true
      end
    end

    context 'when generic inner alias' do
      it 'treats Array<change> vs Array<String> as compatible for alias inner' do
        expect(mod.compatible?('Array<Docscribe::CLI::Formatters::change>', 'Array<String>')).to be true
      end

      it 'treats Array<Integer> vs Array<String> as not compatible' do
        expect(mod.compatible?('Array<Integer>', 'Array<String>')).to be false
      end
    end

    context 'when fallback union' do
      it 'treats Object as compatible with Object fallback' do
        expect(mod.compatible?('String', 'Object', fallback_type: 'Object')).to be true
      end
    end

    it 'uses map dispatch for generic checks' do
      expect(described_class::CHECKS).to be_a(Hash)
    end

    it 'includes expected check keys without hardcoding alias names' do
      expect(described_class::CHECKS.keys).to include(:generic_base, :short_name, :alias_hash, :tuple_array, :optional_nil)
    end

    it 'handles arbitrary user alias with lowercase as compatible' do
      expect(mod.compatible?('My::Custom::my_alias', 'Hash')).to be true
    end

    it 'does not treat capital alias as Hash compatible' do
      expect(mod.compatible?('My::Custom::AnotherAlias', 'Hash')).to be false
    end
  end

  describe 'helper methods' do
    it 'normalizes untyped to Object' do
      expect(mod.normalize('Hash[Symbol, untyped]')).to eq('Hash<Symbol, Object>')
    end

    it 'extracts short name' do
      expect(mod.short_name('Docscribe::CLI::Formatters::change')).to eq('change')
    end

    it 'extracts base name' do
      expect(mod.base_name('Array<String>')).to eq('Array')
    end
  end
end
