# frozen_string_literal: true

module Docscribe
  class Config
    # Decide whether a file path should be processed based on `filter.files`.
    #
    # File paths are matched relative to the current working directory when possible.
    # Exclude rules win. If no include rules are configured, files are included by default.
    #
    # @param [String] path file path to test
    # @raise [StandardError]
    # @return [Boolean]
    def process_file?(path)
      files = raw.dig('filter', 'files') || {}
      include_patterns = normalize_file_patterns(files['include'])
      exclude_patterns = normalize_file_patterns(files['exclude'])

      rel = begin
        Pathname.new(path).expand_path.relative_path_from(Pathname.pwd).cleanpath.to_s
      rescue StandardError
        path
      end

      return false if file_matches_any?(exclude_patterns, rel)
      return true if include_patterns.empty?

      file_matches_any?(include_patterns, rel)
    end

    # Decide whether a method should be processed based on configured method filters.
    #
    # Method IDs are normalized as:
    # - instance method => `MyModule::MyClass#foo`
    # - class method    => `MyModule::MyClass.foo`
    #
    # Exclude rules win. If no include rules are configured, methods are included by default
    # subject to scope and visibility allow-lists.
    #
    # @param [String] container enclosing class/module name
    # @param [Symbol] scope :instance or :class
    # @param [Symbol] visibility :public, :protected, or :private
    # @param [String, Symbol] name method name
    # @return [Boolean]
    def process_method?(container:, scope:, visibility:, name:)
      return false unless filter_scopes.include?(scope.to_s)
      return false unless filter_visibilities.include?(visibility.to_s)

      method_id = "#{container}#{scope == :instance ? '#' : '.'}#{name}"

      return false if matches_any?(filter_exclude_patterns, method_id)

      inc = filter_include_patterns
      return true if inc.empty?

      matches_any?(inc, method_id)
    end

    private

    # Normalize file filter patterns:
    # - compact nils
    # - stringify
    # - remove empties
    # - expand shorthand directory forms
    #
    # @private
    # @param [Array<String>, nil] list raw pattern list
    # @return [Array<String>]
    def normalize_file_patterns(list)
      Array(list).compact.map(&:to_s).reject(&:empty?).flat_map { |pat| expand_directory_shorthand(pat) }.uniq
    end

    # Expand a directory-like pattern into a recursive glob when appropriate.
    #
    # Examples:
    # - `"spec/"` => `"spec/**/*"`
    # - `"spec"` => `"spec/**/*"` if `spec` exists as a directory
    #
    # @private
    # @param [String] pattern
    # @return [Array<String>]
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

    # Check whether a file path matches any configured file pattern.
    #
    # @private
    # @param [Array<String>] patterns
    # @param [String] path
    # @return [Boolean]
    def file_matches_any?(patterns, path)
      patterns.any? { |pat| file_match_pattern?(pat, path) }
    end

    # Match a file path against a single configured file filter.
    #
    # Supports:
    # - `/regex/`
    # - globs
    # - recursive glob shorthand normalization
    #
    # @private
    # @param [String] pattern
    # @param [String] path
    # @return [Boolean]
    def file_match_pattern?(pattern, path)
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        return Regexp.new(pattern[1..-2]).match?(path)
      end

      patterns_to_try = [pattern]
      patterns_to_try << pattern.gsub('/**/', '/') if pattern.include?('/**/')

      patterns_to_try.any? do |pat|
        File.fnmatch?(pat, path, File::FNM_EXTGLOB | File::FNM_DOTMATCH | File::FNM_PATHNAME)
      end
    end

    # Allowed method scopes from config/defaults.
    #
    # @private
    # @return [Array<String>]
    def filter_scopes
      Array(raw.dig('filter', 'scopes') || DEFAULT.dig('filter', 'scopes')).map(&:to_s)
    end

    # Allowed method visibilities from config/defaults.
    #
    # @private
    # @return [Array<String>]
    def filter_visibilities
      Array(raw.dig('filter', 'visibilities') || DEFAULT.dig('filter', 'visibilities')).map(&:to_s)
    end

    # Exclude method filter patterns.
    #
    # @private
    # @return [Array<String>]
    def filter_exclude_patterns
      Array(raw.dig('filter', 'exclude') || DEFAULT.dig('filter', 'exclude')).map(&:to_s).reject(&:empty?)
    end

    # Include method filter patterns.
    #
    # @private
    # @return [Array<String>]
    def filter_include_patterns
      Array(raw.dig('filter', 'include') || DEFAULT.dig('filter', 'include')).map(&:to_s).reject(&:empty?)
    end
  end
end
