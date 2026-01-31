# frozen_string_literal: true

module Docscribe
  class Config
    # Load configuration from YAML.
    #
    # If `path` is provided and exists, it is used. Otherwise, `docscribe.yml`
    # in the current working directory is used if present. If no file is found,
    # defaults are used.
    #
    # @param path [String, nil]
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
    # Ruby 2.7 Psych does not implement `safe_load_file`, so we fall back to reading
    # the file and calling `safe_load`.
    #
    # @param path [String]
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
    # @param yaml [String]
    # @param filename [String, nil]
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
      # Older Psych signature uses positional args
      Psych.safe_load(yaml, [], [], true, filename)
    end
  end
end
