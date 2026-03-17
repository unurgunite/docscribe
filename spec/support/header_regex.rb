# frozen_string_literal: true

module HeaderRegex
  # +HeaderRegex#header_regex+ -> Regexp
  #
  # Method documentation.
  #
  # @param [Object] klass Param documentation.
  # @param [Object] name Param documentation.
  # @param [Object] type Param documentation.
  # @return [Regexp]
  def header_regex(klass, name, type)
    /# \+#{Regexp.escape("#{klass}##{name}")}\+\s*-> #{Regexp.escape(type)}/
  end
end
