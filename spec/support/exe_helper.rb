# frozen_string_literal: true

module ExeHelper
  def exe
    File.expand_path('../../exe/docscribe', __dir__)
  end
end
