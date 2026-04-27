# lib/docscribe/types/rbs/collection_loader.rb
# frozen_string_literal: true

require 'pathname'
require 'yaml'

module Docscribe
  module Types
    module RBS
      # Resolve the RBS collection directory from rbs_collection.lock.yaml.
      #
      # After `bundle exec rbs collection install`, RBS writes a lock-file that
      # records where gem signatures were installed. This loader reads that file
      # so Docscribe can discover the collection directory automatically without
      # requiring the user to pass --sig-dir manually.
      #
      # @example Typical lock-file structure
      #   ---
      #   sources: [...]
      #   path: ".gem_rbs_collection"
      #   gems: [...]
      module CollectionLoader
        LOCK_FILE = 'rbs_collection.lock.yaml'
        DEFAULT_COLLECTION_PATH = '.gem_rbs_collection'

        module_function

        # Resolve the installed RBS collection directory.
        #
        # Returns nil when:
        # - lock-file is absent (collection not initialized)
        # - resolved directory does not exist on disk (collection not installed)
        #
        # @note module_function: when included, also defines #resolve (instance visibility: private)
        # @param [String] root project root to search from
        # @return [String, nil] absolute path to the collection directory, or nil
        def resolve(root: Dir.pwd)
          lock = Pathname(root).join(LOCK_FILE)
          return nil unless lock.file?

          data = YAML.safe_load(lock.read, permitted_classes: [Symbol]) || {}
          rel  = data['path'] || DEFAULT_COLLECTION_PATH

          resolved = Pathname(root).join(rel)
          resolved.directory? ? resolved.expand_path.to_s : nil
        end
      end
    end
  end
end
