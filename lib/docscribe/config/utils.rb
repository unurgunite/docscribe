# frozen_string_literal: true

module Docscribe
  class Config
    private

    # Fetch a boolean method-level override for a given scope/visibility pair.
    #
    # @private
    # @param [Symbol] scope :instance or :class
    # @param [Symbol] vis :public, :protected, or :private
    # @param [String] key override key
    # @param [Boolean] default fallback value
    # @return [Boolean]
    def method_override_bool(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : !!node
    end

    # Fetch a string method-level override for a given scope/visibility pair.
    #
    # @private
    # @param [Symbol] scope :instance or :class
    # @param [Symbol] vis :public, :protected, or :private
    # @param [String] key override key
    # @param [String] default fallback value
    # @return [String]
    def method_override_str(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : node.to_s
    end

    # Fetch a boolean config value by nested path with a default fallback.
    #
    # @private
    # @param [Array<String>] path nested config keys
    # @param [Boolean] default fallback value
    # @return [Boolean]
    def fetch_bool(path, default)
      node = raw
      path.each { |k| node = node[k] if node }
      node.nil? ? default : !!node
    end

    # Convert an internal scope symbol into the config key used under `methods`.
    #
    # @private
    # @param [Symbol] scope
    # @return [String]
    def scope_to_key(scope)
      scope == :class ? 'class' : 'instance'
    end

    # Check whether any pattern matches the given text.
    #
    # @private
    # @param [Array<String>] patterns
    # @param [String] text
    # @return [Boolean]
    def matches_any?(patterns, text)
      patterns.any? { |pat| match_pattern?(pat, text) }
    end

    # Match a method filter pattern against a method ID.
    #
    # Supports:
    # - `/regex/`
    # - shell-style glob patterns
    #
    # @private
    # @param [String] pattern
    # @param [String] text
    # @return [Boolean]
    def match_pattern?(pattern, text)
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        Regexp.new(pattern[1..-2]).match?(text)
      else
        File.fnmatch?(pattern, text, File::FNM_EXTGLOB)
      end
    end

    # Deep-merge two hashes, preferring values from the second hash.
    #
    # Nested hashes are merged recursively; non-hash values are replaced.
    #
    # @private
    # @param [Hash] hash1 base hash
    # @param [Hash, nil] hash2 override hash
    # @return [Hash]
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
