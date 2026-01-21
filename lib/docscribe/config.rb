# frozen_string_literal: true

require 'yaml'
require 'pathname'

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
        'exclude' => [],
        'files' => {
          'include' => [],
          'exclude' => []
        }
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

    # Returns the default config file contents for `docscribe init`.
    #
    # Keep this in sync with Config defaults.
    #
    # @return [String]
    def self.default_yaml
      <<~YAML
        # Docscribe configuration file
        #
        # CI check (fails if any file would change):
        #   bundle exec docscribe --check lib
        #
        # Auto-fix (rewrites files):
        #   bundle exec docscribe --write lib
        #
        # Regenerate docs even if a comment block already exists:
        #   bundle exec docscribe --rewrite --write lib
        #

        emit:
          header: true
          param_tags: true
          return_tag: true
          visibility_tags: true
          raise_tags: true
          rescue_conditional_returns: true

        doc:
          default_message: "Method documentation."

        methods:
          instance:
            public: {}
            protected: {}
            private: {}
          class:
            public: {}
            protected: {}
            private: {}

        inference:
          fallback_type: "Object"
          nil_as_optional: true
          treat_options_keyword_as_hash: true

        # Filter which methods Docscribe touches.
        #
        # Method id format:
        #   "MyModule::MyClass#instance_method"
        #   "MyModule::MyClass.class_method"
        #
        # Patterns:
        # - glob strings like "*#initialize", "MyApp::*#*"
        # - or regex strings like "/^MyApp::.*#(foo|bar)$/"
        #
        # Semantics:
        # - scopes/visibilities act as allow-lists
        # - exclude always wins
        # - if include is empty => include everything (subject to allow-lists)
        filter:
          visibilities: ["public", "protected", "private"]
          scopes: ["instance", "class"]
          include: []
          exclude: []
          files:
            include: []
            exclude: []
      YAML
    end

    # Return true if this file path should be processed.
    #
    # @param [String] path a file path as passed from the CLI
    # @return [Boolean]
    def process_file?(path)
      files = raw.dig('filter', 'files') || {}
      include_patterns = normalize_file_patterns(files['include'])
      exclude_patterns = normalize_file_patterns(files['exclude'])

      # Compare against a clean, relative path (best UX for patterns like "spec/**/*.rb")
      rel = begin
        Pathname.new(path).relative_path_from(Pathname.pwd).to_s
      rescue StandardError
        path
      end

      # Exclude wins
      return false if file_matches_any?(exclude_patterns, rel)

      # Empty include means “include everything”
      return true if include_patterns.empty?

      file_matches_any?(include_patterns, rel)
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

    # +Docscribe::Config#process_method?+ -> Boolean
    #
    # Returns true if this method should be processed by Docscribe.
    #
    # @param [String] container e.g. "MyApp::User"
    # @param [Symbol] scope :instance or :class
    # @param [Symbol] visibility :public, :protected, :private
    # @param [String, Symbol] name method name
    # @return [Boolean]
    def process_method?(container:, scope:, visibility:, name:)
      scopes = Array(raw.dig('filter', 'scopes')).map(&:to_s)
      visibilities = Array(raw.dig('filter', 'visibilities')).map(&:to_s)
      return false unless scopes.include?(scope.to_s)
      return false unless visibilities.include?(visibility.to_s)

      method_id = "#{container}#{scope == :instance ? '#' : '.'}#{name}"
      exclude = normalize_patterns(raw.dig('filter', 'exclude'))
      include_ = normalize_patterns(raw.dig('filter', 'include'))
      # Exclude always wins
      return false if matches_any?(exclude, method_id)
      # Empty include means "include everything"
      return true if include_.empty?

      matches_any?(include_, method_id)
    end

    private

    def normalize_file_patterns(list)
      Array(list).compact.map(&:to_s).reject(&:empty?).flat_map do |pat|
        expand_directory_shorthand(pat)
      end.uniq
    end

    def expand_directory_shorthand(pattern)
      pat = pattern.dup

      if pat.end_with?('/')
        ["#{pat}**/*"]
      elsif !pat.match?(/[*?\[]|{/) && File.directory?(pat)
        ["#{pat}/**/*"]
      else
        [pat]
      end
    end

    def file_matches_any?(patterns, path)
      patterns.any? { |pat| file_match_pattern?(pat, path) }
    end

    def file_match_pattern?(pattern, path)
      # Regex form: "/.../"
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        return Regexp.new(pattern[1..-2]).match?(path)
      end

      # Globstar fix:
      # If pattern contains "/**/", also try the “zero dirs” variant by collapsing it to "/"
      patterns_to_try = [pattern]
      patterns_to_try << pattern.gsub('/**/', '/') if pattern.include?('/**/')

      patterns_to_try.any? do |pat|
        File.fnmatch?(pat, path, File::FNM_EXTGLOB | File::FNM_PATHNAME)
      end
    end

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

    def normalize_patterns(list)
      Array(list).compact.map(&:to_s).reject(&:empty?)
    end

    def matches_any?(patterns, text)
      patterns.any? { |pat| match_pattern?(pat, text) }
    end

    def match_pattern?(pattern, text)
      # Regex syntax: "/.../"
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        Regexp.new(pattern[1..-2]).match?(text)
      else
        File.fnmatch?(pattern, text, File::FNM_EXTGLOB)
      end
    end

    def filter_scopes
      Array(raw.dig('filter', 'scopes') || DEFAULT.dig('filter', 'scopes')).map(&:to_s)
    end

    def filter_visibilities
      Array(raw.dig('filter', 'visibilities') || DEFAULT.dig('filter', 'visibilities')).map(&:to_s)
    end

    def filter_exclude_patterns
      Array(raw.dig('filter', 'exclude')).map(&:to_s).reject(&:empty?)
    end

    def filter_include_patterns
      Array(raw.dig('filter', 'include')).map(&:to_s).reject(&:empty?)
    end
  end
end
