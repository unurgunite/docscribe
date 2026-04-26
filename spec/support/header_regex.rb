# frozen_string_literal: true

module HeaderRegex
  # Build a regex that matches a generated YARD doc header comment line.
  #
  # Matches patterns like: `# +ClassName#method_name+ -> ReturnType`
  #
  # @param [String] klass class or module name (e.g. "Demo")
  # @param [String, Symbol] name method name (e.g. "foo")
  # @param [String] type return type (e.g. "Integer")
  # @return [Regexp]
  def header_regex(klass, name, type)
    /# \+#{Regexp.escape("#{klass}##{name}")}\+\s*-> #{Regexp.escape(type)}/
  end
end
