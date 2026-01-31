# frozen_string_literal: true

module Docscribe
  class Config
    private

    def method_override_bool(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : !!node
    end

    def method_override_str(scope, vis, key, default:)
      node = raw.dig('methods', scope_to_key(scope), vis.to_s, key)
      node.nil? ? default : node.to_s
    end

    def fetch_bool(path, default)
      node = raw
      path.each { |k| node = node[k] if node }
      node.nil? ? default : !!node
    end

    def scope_to_key(scope)
      scope == :class ? 'class' : 'instance'
    end

    def matches_any?(patterns, text)
      patterns.any? { |pat| match_pattern?(pat, text) }
    end

    def match_pattern?(pattern, text)
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        Regexp.new(pattern[1..-2]).match?(text)
      else
        File.fnmatch?(pattern, text, File::FNM_EXTGLOB)
      end
    end

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
