# frozen_string_literal: true

module Docscribe
  class Config
    # Default configuration template used by `docscribe init`.
    #
    # @return [String]
    def self.default_yaml
      <<~YAML
        # Docscribe configuration file (docscribe.yml)
        #
        # Common workflows:
        #   # CI check (fails if any file would change):
        #   bundle exec docscribe --dry lib
        #
        #   # Auto-fix (rewrites files):
        #   bundle exec docscribe --write lib
        #
        #   # Refresh/rebaseline (replaces existing doc blocks):
        #   bundle exec docscribe --write --refresh lib
        #

        emit:
          # Emit the header line:
          #   # +MyClass#my_method+ -> ReturnType
          header: true

          # Emit @param tags.
          param_tags: true

          # Emit @return tag (can be overridden per scope/visibility under methods:).
          return_tag: true

          # Emit @private / @protected tags based on Ruby visibility context.
          visibility_tags: true

          # Emit @raise tags inferred from rescue clauses / raise/fail calls.
          raise_tags: true

          # Emit conditional rescue return tags:
          #   # @return [String] if FooError, BarError
          rescue_conditional_returns: true

        doc:
          # Default text inserted into each generated doc block.
          default_message: "Method documentation."

        methods:
          # Per-scope/per-visibility overrides.
          #
          # Example:
          #   methods:
          #     instance:
          #       public:
          #         default_message: "Public API."
          #         return_tag: true
          instance:
            public: {}
            protected: {}
            private: {}
          class:
            public: {}
            protected: {}
            private: {}

        inference:
          # Type used when inference is uncertain.
          fallback_type: "Object"

          # Whether nil unions become Optional types (e.g. String + nil => String?).
          nil_as_optional: true

          # Special-case: treat keyword arg named options/options: as a Hash.
          treat_options_keyword_as_hash: true

        filter:
          # Filter which methods Docscribe touches.
          #
          # Method id format:
          #   instance: "MyModule::MyClass#instance_method"
          #   class:    "MyModule::MyClass.class_method"
          #
          # Patterns:
          # - glob: "*#initialize", "MyApp::*#*"
          # - regex: "/^MyApp::.*#(foo|bar)$/"
          #
          # Semantics:
          # - scopes/visibilities act as allow-lists
          # - exclude wins
          # - if include is empty => include everything (subject to allow-lists)

          visibilities: ["public", "protected", "private"]
          scopes: ["instance", "class"]
          include: []
          exclude: []

          files:
            # Filter which files Docscribe processes (paths are matched relative to the project root).
            #
            # Tips:
            # - Use directory shorthand to exclude a whole directory:
            #     exclude: ["spec"]
            #
            # - Or use globs:
            #     exclude: ["spec/**/*.rb", "vendor/**/*.rb"]
            include: []
            exclude: ["spec"]

        rbs:
          # Optional: use RBS signatures to improve @param/@return types.
          #
          # CLI equivalent:
          #   bundle exec docscribe --rbs --sig-dir sig --write lib
          #
          # Note: under Bundler, you may need `gem "rbs"` in your Gemfile (or a Gemfile that includes it),
          # otherwise `require "rbs"` may fail and Docscribe will fall back to inference.
          enabled: false

          # Signature directories (repeatable via --sig-dir).
          sig_dirs: ["sig"]

          # If true, simplify generic types:
          #   Hash<Symbol, Object> => Hash
          #   Array<String>        => Array
          collapse_generics: false
      YAML
    end
  end
end
