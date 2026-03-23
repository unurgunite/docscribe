# frozen_string_literal: true

module Docscribe
  class Config
    # Load Docscribe configuration from YAML.
    #
    # Resolution order:
    # - explicit `path`, if it exists
    # - `docscribe.yml` in the current directory, if present
    # - otherwise defaults only
    #
    # @param [String, nil] path optional config path
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
    # Uses `YAML.safe_load_file` when available, otherwise falls back to reading the file
    # and calling {safe_load_compat}.
    #
    # @param [String] path file path
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
    # @param [String] yaml YAML document
    # @param [String, nil] filename optional filename for diagnostics
    # @raise [ArgumentError]
    # @return [Hash]
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
