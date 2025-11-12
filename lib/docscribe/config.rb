# frozen_string_literal: true

require 'yaml'

module Docscribe
  class Config
    DEFAULT = {
      'emit' => {
        'header' => true,
        'param_tags' => true,
        'return_tag' => true,
        'visibility_tags' => true,
        'raise_tags' => true,
        'rescue_conditional_returns' => true
      },
      'doc' => {
        'default_message' => 'Method documentation.'
      },
      'methods' => {
        'instance' => {
          'public' => {},
          'protected' => {},
          'private' => {}
        },
        'class' => {
          'public' => {},
          'protected' => {},
          'private' => {}
        }
      },
      'inference' => {
        'fallback_type' => 'Object',
        'nil_as_optional' => true,
        'treat_options_keyword_as_hash' => true
      },
      'filter' => {
        'visibilities' => %w[public protected private],
        'scopes' => %w[instance class],
        'include' => [],
        'exclude' => []
      }
    }.freeze

    attr_reader :raw

    # +Docscribe::Config#initialize+ -> Object
    #
    # Method documentation.
    #
    # @param [Hash] raw Param documentation.
    # @return [Object]
    def initialize(raw = {})
      @raw = deep_merge(DEFAULT, raw || {})
    end

    # +Docscribe::Config.load+ -> Object
    #
    # Method documentation.
    #
    # @param [nil] path Param documentation.
    # @return [Object]
    def self.load(path = nil)
      raw = {}
      if path && File.file?(path)
        raw = YAML.safe_load_file(path, permitted_classes: [], aliases: true) || {}
      elsif File.file?('docscribe.yml')
        raw = YAML.safe_load_file('docscribe.yml', permitted_classes: [], aliases: true) || {}
      end
      new(raw)
    end

    # +Docscribe::Config#emit_header?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def emit_header?
      fetch_bool(%w[emit header], true)
    end

    # +Docscribe::Config#emit_param_tags?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def emit_param_tags?
      fetch_bool(%w[emit param_tags], true)
    end

    # +Docscribe::Config#emit_visibility_tags?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def emit_visibility_tags?
      fetch_bool(%w[emit visibility_tags], true)
    end

    # +Docscribe::Config#emit_raise_tags?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def emit_raise_tags?
      fetch_bool(%w[emit raise_tags], true)
    end

    # +Docscribe::Config#emit_rescue_conditional_returns?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def emit_rescue_conditional_returns?
      fetch_bool(%w[emit rescue_conditional_returns], true)
    end

    # +Docscribe::Config#emit_return_tag?+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] scope Param documentation.
    # @param [Object] visibility Param documentation.
    # @return [Object]
    def emit_return_tag?(scope, visibility)
      method_override_bool(scope, visibility, 'return_tag',
                           default: fetch_bool(%w[emit return_tag], true))
    end

    # +Docscribe::Config#default_message+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] scope Param documentation.
    # @param [Object] visibility Param documentation.
    # @return [Object]
    def default_message(scope, visibility)
      method_override_str(scope, visibility, 'default_message',
                          default: raw.dig('doc', 'default_message') || 'Method documentation.')
    end

    # +Docscribe::Config#fallback_type+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def fallback_type
      raw.dig('inference', 'fallback_type') || 'Object'
    end

    # +Docscribe::Config#nil_as_optional?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def nil_as_optional?
      fetch_bool(%w[inference nil_as_optional], true)
    end

    # +Docscribe::Config#treat_options_keyword_as_hash?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def treat_options_keyword_as_hash?
      fetch_bool(%w[inference treat_options_keyword_as_hash], true)
    end

    private

    # +Docscribe::Config#method_override_bool+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] scope Param documentation.
    # @param [Object] vis Param documentation.
    # @param [Object] key Param documentation.
    # @param [Object] default Param documentation.
    # @return [Object]
    def method_override_bool(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : !!node
    end

    # +Docscribe::Config#fetch_bool+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] path Param documentation.
    # @param [Object] default Param documentation.
    # @return [Object]
    def fetch_bool(path, default)
      node = raw
      path.each { |k| node = node[k] if node }
      node.nil? ? default : !!node
    end

    # +Docscribe::Config#method_override_str+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] scope Param documentation.
    # @param [Object] vis Param documentation.
    # @param [Object] key Param documentation.
    # @param [Object] default Param documentation.
    # @return [Object]
    def method_override_str(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : node.to_s
    end

    # +Docscribe::Config#scope_to_key+ -> String
    #
    # Method documentation.
    #
    # @private
    # @param [Object] scope Param documentation.
    # @return [String]
    def scope_to_key(scope)
      scope == :class ? 'class' : 'instance'
    end

    # +Docscribe::Config#deep_merge+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] hash1 Param documentation.
    # @param [Object] hash2 Param documentation.
    # @return [Object]
    def deep_merge(hash1, hash2)
      return hash1 unless hash2

      hash1.merge(hash2) do |_, v1, v2|
        if v1.is_a?(Hash) && v2.is_a?(Hash)
          deep_merge(v1, v2)
        else
          v2
        end
      end
    end
  end
end
