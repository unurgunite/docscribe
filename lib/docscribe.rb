# frozen_string_literal: true

module Docscribe
  class Error < StandardError; end
end

require_relative 'docscribe/version'
require_relative 'docscribe/config'
require_relative 'docscribe/infer'
require_relative 'docscribe/inline_rewriter'
