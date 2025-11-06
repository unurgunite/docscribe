# frozen_string_literal: true

module HeaderRegex
  def header_regex(klass, name, type)
    /\# \+#{Regexp.escape("#{klass}##{name}")}\+\s*-> #{Regexp.escape(type)}/
  end
end
