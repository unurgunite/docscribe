# frozen_string_literal: true

require 'yaml'

RSpec.describe Docscribe::Config do
  let(:default) { Docscribe::Config::DEFAULT }
  let(:yaml) { YAML.safe_load(described_class.default_yaml) }

  describe 'defaults' do
    it { expect(default).to eq(yaml) }
  end

  describe 'emit section' do
    %w[header param_tags return_tag visibility_tags raise_tags
       rescue_conditional_returns attributes].each do |key|
      it "matches emit.#{key}" do
        expect(yaml.dig('emit', key)).to eq(default.dig('emit', key))
      end
    end
  end

  describe 'doc section' do
    it 'matches between DEFAULT hash and template YAML' do
      %w[default_message param_tag_style param_documentation sort_tags].each do |key|
        expect(yaml.dig('doc', key))
          .to eq(default.dig('doc', key)),
              "Mismatch for doc.#{key}"
      end
    end

    it 'has matching tag_order arrays' do
      yaml_order = (yaml.dig('doc', 'tag_order') || []).map { |t| t.to_s.sub(/\A@/, '') }
      default_order = (default.dig('doc', 'tag_order') || []).map { |t| t.to_s.sub(/\A@/, '') }
      expect(yaml_order).to eq(default_order)
    end
  end

  describe 'inference section' do
    %w[fallback_type nil_as_optional treat_options_keyword_as_hash].each do |key|
      it "matches inference.#{key}" do
        expect(yaml.dig('inference', key)).to eq(default.dig('inference', key))
      end
    end
  end

  describe 'filter section' do
    it 'has matching visibilities and scopes', :aggregate_failures do
      expect(yaml.dig('filter', 'visibilities'))
        .to match_array(default.dig('filter', 'visibilities'))
      expect(yaml.dig('filter', 'scopes'))
        .to match_array(default.dig('filter', 'scopes'))
    end
  end

  describe 'rbs section' do
    it 'has matching enabled and collapse settings', :aggregate_failures do
      expect(yaml.dig('rbs', 'enabled')).to eq(default.dig('rbs', 'enabled'))
      expect(yaml.dig('rbs', 'collapse_generics')).to eq(default.dig('rbs', 'collapse_generics'))
      expect(yaml.dig('rbs', 'collapse_object_generics')).to eq(default.dig('rbs', 'collapse_object_generics'))
      expect(yaml.dig('rbs', 'sig_dirs')).to match_array(default.dig('rbs', 'sig_dirs'))
    end
  end

  describe 'sorbet section' do
    it 'has matching enabled and collapse settings', :aggregate_failures do
      expect(yaml.dig('sorbet', 'enabled')).to eq(default.dig('sorbet', 'enabled'))
      expect(yaml.dig('sorbet', 'collapse_generics')).to eq(default.dig('sorbet', 'collapse_generics'))
      expect(yaml.dig('sorbet', 'collapse_object_generics')).to eq(default.dig('sorbet', 'collapse_object_generics'))
      expect(yaml.dig('sorbet', 'rbi_dirs')).to match_array(default.dig('sorbet', 'rbi_dirs'))
    end
  end
end
