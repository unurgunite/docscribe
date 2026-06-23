# frozen_string_literal: true

module CleanFileHelper
  def create_clean_file(socket_path)
    path = "#{File.dirname(socket_path)}/clean.rb"
    File.write(path, "# Documented method\n# @return [String]\ndef greet\n  'hello'\nend\n")
    path
  end
end
