# frozen_string_literal: true

module Docscribe
  class Config
    # Decide whether a file path should be processed based on `filter.files`.
    #
    # Patterns are matched against paths relative to the current working directory.
    # Supported patterns:
    # - glob strings (e.g. "spec", "spec/**/*.rb")
    # - regex strings wrapped in slashes (e.g. "/^spec\\//")
    #
    # Exclude wins. If include is empty, everything is included.
    #
    # @param path [String]
    # @return [Boolean]
    def process_file?(path)
      files = raw.dig('filter', 'files') || {}
      include_patterns = normalize_file_patterns(files['include'])
      exclude_patterns = normalize_file_patterns(files['exclude'])

      rel = begin
        Pathname.new(path).relative_path_from(Pathname.pwd).to_s
      rescue StandardError
        path
      end

      return false if file_matches_any?(exclude_patterns, rel)
      return true if include_patterns.empty?

      file_matches_any?(include_patterns, rel)
    end

    # Decide whether a method should be processed based on `filter` rules.
    #
    # Method id format:
    # - instance: "MyModule::MyClass#method_name"
    # - class:    "MyModule::MyClass.method_name"
    #
    # Exclude wins. If include is empty, everything is included (subject to scope/visibility allow-lists).
    #
    # @param container [String]
    # @param scope [Symbol]
    # @param visibility [Symbol]
    # @param name [String, Symbol]
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

    def normalize_file_patterns(list)
      Array(list).compact.map(&:to_s).reject(&:empty?).flat_map { |pat| expand_directory_shorthand(pat) }.uniq
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
      if pattern.start_with?('/') && pattern.end_with?('/') && pattern.length >= 2
        return Regexp.new(pattern[1..-2]).match?(path)
      end

      patterns_to_try = [pattern]
      patterns_to_try << pattern.gsub('/**/', '/') if pattern.include?('/**/')

      patterns_to_try.any? do |pat|
        File.fnmatch?(pat, path, File::FNM_EXTGLOB | File::FNM_PATHNAME)
      end
    end

    def filter_scopes
      Array(raw.dig('filter', 'scopes') || DEFAULT.dig('filter', 'scopes')).map(&:to_s)
    end

    def filter_visibilities
      Array(raw.dig('filter', 'visibilities') || DEFAULT.dig('filter', 'visibilities')).map(&:to_s)
    end

    def filter_exclude_patterns
      Array(raw.dig('filter', 'exclude') || DEFAULT.dig('filter', 'exclude')).map(&:to_s).reject(&:empty?)
    end

    def filter_include_patterns
      Array(raw.dig('filter', 'include') || DEFAULT.dig('filter', 'include')).map(&:to_s).reject(&:empty?)
    end
  end
end
