# frozen_string_literal: true

module StingrayDocsInternal
  class Error < StandardError; end
end

require_relative 'stingray_docs_internal/version'
require_relative 'stingray_docs_internal/infer'
require_relative 'stingray_docs_internal/inline_rewriter'
