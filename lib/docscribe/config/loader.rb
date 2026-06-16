# frozen_string_literal: true

module Docscribe
  # YAML config file loading and resolution.
  class Config
    # Load Docscribe configuration from YAML.
    #
    # Resolution order:
    # - explicit `path`, if it exists
    # - `docscribe.yml` in the current directory, if present
    # - otherwise defaults only
    #
    # @param [String?] path optional config path
    # @return [Docscribe::Config]
    def self.load(path = nil)
      raw = {} #: Hash[String, untyped]
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
    # @return [Hash<String, Object>]
    def self.safe_load_file_compat(path)
      if YAML.respond_to?(:safe_load_file) # steep:ignore
        pclasses = [] #: Array[String]
        psymbols = [] #: Array[Symbol]
        YAML.safe_load_file(path, # steep:ignore
                            permitted_classes: pclasses, permitted_symbols: psymbols,
                            aliases: true) || {} #: Hash[String, untyped]
      else
        yaml = File.open(path, 'r:bom|utf-8', &:read)
        safe_load_compat(yaml, filename: path) || {} #: Hash[String, untyped]
      end
    end

    # Safely load YAML from a string across Psych API versions.
    #
    # @param [String] yaml YAML document
    # @param [String?] filename optional filename for diagnostics
    # @raise [ArgumentError]
    # @return [Hash<String, Object>] if ArgumentError
    # @return [Object] if ArgumentError
    def self.safe_load_compat(yaml, filename: nil)
      pclasses = [] #: Array[String]
      psymbols = [] #: Array[Symbol]
      Psych.safe_load( # steep:ignore
        yaml,
        permitted_classes: pclasses, permitted_symbols: psymbols,
        aliases: true,
        filename: filename
      ) #: Hash[String, untyped]
    rescue ArgumentError
      # Older Psych signature uses positional args
      Psych.safe_load(yaml, [], [], true, filename) # steep:ignore
    end
  end
end
