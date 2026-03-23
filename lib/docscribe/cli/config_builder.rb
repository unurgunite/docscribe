# frozen_string_literal: true

require 'docscribe/config'

module Docscribe
  module CLI
    module ConfigBuilder
      module_function

      def build(base, options)
        needs_override =
          options[:include].any? ||
          options[:exclude].any? ||
          options[:include_file].any? ||
          options[:exclude_file].any? ||
          options[:rbs] ||
          options[:sig_dirs].any? ||
          options[:sorbet] ||
          options[:rbi_dirs].any?

        return base unless needs_override

        raw = Marshal.load(Marshal.dump(base.raw))

        raw['filter'] ||= {}
        raw['filter']['include'] = Array(raw['filter']['include']) + options[:include]
        raw['filter']['exclude'] = Array(raw['filter']['exclude']) + options[:exclude]

        raw['filter']['files'] ||= {}
        raw['filter']['files']['include'] = Array(raw['filter']['files']['include']) + options[:include_file]
        raw['filter']['files']['exclude'] = Array(raw['filter']['files']['exclude']) + options[:exclude_file]

        if options[:rbs] || options[:sig_dirs].any?
          raw['rbs'] ||= {}
          raw['rbs']['enabled'] = true
          raw['rbs']['sig_dirs'] = Array(raw['rbs']['sig_dirs']) + options[:sig_dirs] if options[:sig_dirs].any?
        end

        if options[:sorbet] || options[:rbi_dirs].any?
          raw['sorbet'] ||= {}
          raw['sorbet']['enabled'] = true
          raw['sorbet']['rbi_dirs'] = Array(raw['sorbet']['rbi_dirs']) + options[:rbi_dirs] if options[:rbi_dirs].any?
        end

        Docscribe::Config.new(raw)
      end
    end
  end
end
