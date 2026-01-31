# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'psych'

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
      },
      'rbs' => {
        'enabled' => false,
        'sig_dirs' => ['sig'],
        'collapse_generics' => false
      }
    }.freeze

    attr_reader :raw

    # +Docscribe::Config#initialize+ -> Object
    #
    # `raw` is merged into {DEFAULT}. Any missing keys are filled from defaults.
    #
    # @param raw [Hash, nil] user configuration loaded from YAML (or overrides)
    # @return [Object]
    def initialize(raw = {})
      @raw = deep_merge(DEFAULT, raw || {})
    end

    # +Docscribe::Config.load+ -> Object
    #
    # Load configuration from YAML.
    #
    # If `path` is provided and exists, it is used. Otherwise, `docscribe.yml`
    # in the current working directory is used if present. If no file is found,
    # defaults are used.
    #
    # @param path [String, nil] optional path to a YAML config
    # @return [Docscribe::Config]
    def self.load(path = nil)
      raw = {}
      if path && File.file?(path)
        raw = safe_load_file_compat(path)
      elsif File.file?('docscribe.yml')
        raw = safe_load_file_compat('docscribe.yml')
      end
      new(raw)
    end

    # Safely load YAML from a file across Ruby/Psych versions.
    #
    # Ruby 2.7 Psych does not implement `safe_load_file`, so we fall back to
    # reading the file and calling `safe_load`.
    #
    # @param [String] path
    # @return [Hash]
    def self.safe_load_file_compat(path)
      if YAML.respond_to?(:safe_load_file)
        YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true) || {}
      else
        yaml = File.open(path, 'r:bom|utf-8', &:read)
        safe_load_compat(yaml, filename: path) || {}
      end
    end

    # Safely load YAML from a string across Psych API versions.
    #
    # @param [String] yaml
    # @param [String, nil] filename
    # @return [Object]
    def self.safe_load_compat(yaml, filename: nil)
      Psych.safe_load(
        yaml,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: true,
        filename: filename
      )
    rescue ArgumentError
      Psych.safe_load(yaml, [], [], true, filename)
    end

    # +Docscribe::Config.load+ -> Object
    #
    # Default configuration file template used by `docscribe init`.
    #
    # @return [String] YAML contents for a starter `docscribe.yml`
    def self.default_yaml
      <<~YAML
        # Docscribe configuration file
        #
        # CI check (fails if any file would change):
        #   bundle exec docscribe --dry lib
        #
        # Auto-fix (rewrites files):
        #   bundle exec docscribe --write lib
        #
        # Regenerate docs even if a comment block already exists:
        #   bundle exec docscribe --refresh --write lib
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

        rbs:
          enabled: false
          sig_dirs: ["sig"]
          collapse_generics: false
      YAML
    end

    # Decide whether a file should be processed based on `filter.files`.
    #
    # Patterns are matched against paths relative to the current working directory.
    # Supported patterns:
    # - glob strings (e.g. "spec", "spec/**/*.rb")
    # - regex strings wrapped in slashes (e.g. "/^spec\\//")
    #
    # Exclude wins. If include is empty, everything is included.
    #
    # @param path [String] file path from CLI expansion
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
    # Decide whether a method should be processed based on `filter` rules.
    #
    # Method id format:
    # - instance: "MyModule::MyClass#method_name"
    # - class:    "MyModule::MyClass.method_name"
    #
    # Exclude wins. If include is empty, everything is included (subject to
    # scope/visibility allow-lists).
    #
    # @param container [String] e.g. "MyApp::User"
    # @param scope [Symbol] :instance or :class
    # @param visibility [Symbol] :public, :protected, :private
    # @param name [String, Symbol] method name
    # @return [Boolean]
    def process_method?(container:, scope:, visibility:, name:)
      return false unless filter_scopes.include?(scope.to_s)
      return false unless filter_visibilities.include?(visibility.to_s)

      method_id = "#{container}#{scope == :instance ? '#' : '.'}#{name}"
      # Exclude always wins
      return false if matches_any?(filter_exclude_patterns, method_id)

      # Empty include means "include everything"
      inc = filter_include_patterns
      return true if inc.empty?

      matches_any?(inc, method_id)
    end

    # Memoized RBS provider (nil if disabled or RBS is unavailable).
    #
    # @return [Docscribe::Types::RBSProvider, nil]
    def rbs_provider
      return nil unless rbs_enabled?

      @rbs_provider ||= begin
        require 'docscribe/types/rbs_provider'
        Docscribe::Types::RBSProvider.new(
          sig_dirs: rbs_sig_dirs,
          collapse_generics: rbs_collapse_generics?
        )
      rescue LoadError
        nil
      end
    end

    # Whether RBS integration is enabled.
    #
    # @return [Boolean]
    def rbs_enabled?
      fetch_bool(%w[rbs enabled], false)
    end

    # Directories to load RBS signatures from (typically ["sig"]).
    #
    # @return [Array<String>]
    def rbs_sig_dirs
      Array(raw.dig('rbs', 'sig_dirs') || DEFAULT.dig('rbs', 'sig_dirs')).map(&:to_s)
    end

    # +Docscribe::Config#rbs_collapse_generics?+ -> Object
    #
    # Method documentation.
    #
    # @return [Object]
    def rbs_collapse_generics?
      fetch_bool(%w[rbs collapse_generics], false)
    end

    private

    # +Docscribe::Config#normalize_file_patterns+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] list Param documentation.
    # @return [Object]
    def normalize_file_patterns(list)
      Array(list).compact.map(&:to_s).reject(&:empty?).flat_map do |pat|
        expand_directory_shorthand(pat)
      end.uniq
    end

    # +Docscribe::Config#expand_directory_shorthand+ -> Array
    #
    # Method documentation.
    #
    # @private
    # @param [Object] pattern Param documentation.
    # @return [Array]
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

    # +Docscribe::Config#file_matches_any?+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] patterns Param documentation.
    # @param [Object] path Param documentation.
    # @return [Object]
    def file_matches_any?(patterns, path)
      patterns.any? { |pat| file_match_pattern?(pat, path) }
    end

    # +Docscribe::Config#file_match_pattern?+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] pattern Param documentation.
    # @param [Object] path Param documentation.
    # @return [Object]
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

    # +Docscribe::Config#filter_scopes+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @return [Object]
    def filter_scopes
      Array(raw.dig('filter', 'scopes') || DEFAULT.dig('filter', 'scopes')).map(&:to_s)
    end

    # +Docscribe::Config#filter_visibilities+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @return [Object]
    def filter_visibilities
      Array(raw.dig('filter', 'visibilities') || DEFAULT.dig('filter', 'visibilities')).map(&:to_s)
    end

    # +Docscribe::Config#matches_any?+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] patterns Param documentation.
    # @param [Object] text Param documentation.
    # @return [Object]
    def matches_any?(patterns, text)
      patterns.any? { |pat| match_pattern?(pat, text) }
    end

    # +Docscribe::Config#match_pattern?+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @param [Object] pattern Param documentation.
    # @param [Object] text Param documentation.
    # @return [Object]
    def match_pattern?(pattern, text)
      # Regex syntax: "/.../"
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        Regexp.new(pattern[1..-2]).match?(text)
      else
        File.fnmatch?(pattern, text, File::FNM_EXTGLOB)
      end
    end

    # +Docscribe::Config#filter_exclude_patterns+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @return [Object]
    def filter_exclude_patterns
      Array(raw.dig('filter', 'exclude')).map(&:to_s).reject(&:empty?)
    end

    # @private
    def filter_include_patterns
      Array(raw.dig('filter', 'include') || DEFAULT.dig('filter', 'include')).map(&:to_s).reject(&:empty?)
    end
  end
end
