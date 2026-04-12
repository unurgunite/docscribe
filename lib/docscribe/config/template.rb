# frozen_string_literal: true

module Docscribe
  class Config
    # Return the default YAML template used by `docscribe init`.
    #
    # The template documents the most common CLI workflows and all supported
    # configuration sections with comments.
    # @see Docscribe::Config::DEFAULT
    #
    # @return [String]
    def self.default_yaml
      <<~YAML
        ---
        # Docscribe configuration file
        #
        # Inspect what safe doc updates would be applied:
        #   bundle exec docscribe lib
        #
        # Apply safe doc updates:
        #   bundle exec docscribe -a lib
        #
        # Apply aggressive doc updates (rebuild existing doc blocks):
        #   bundle exec docscribe -A lib
        #

        emit:
          # Emit the header line:
          #
          #   +MyClass#my_method+ -> ReturnType
          header: false

          # Whether to include the default placeholder line:
          #   # Method documentation.
          include_default_message: true

          # Whether to append placeholder text to generated @param tags:
          #   # @param [String] name Param documentation.
          include_param_documentation: true

          # Emit @param tags.
          param_tags: true

          # Emit @return tag (can be overridden per scope/visibility under methods:).
          return_tag: true

          # Emit @private / @protected tags based on Ruby visibility context.
          visibility_tags: true

          # Emit @raise tags inferred from rescue clauses / raise/fail calls.
          raise_tags: true

          # Emit conditional rescue return tags:
          #
          #   @return [String] if FooError, BarError
          rescue_conditional_returns: true

          # Generate @!attribute docs for attr_reader/attr_writer/attr_accessor.
          attributes: false

        doc:
          # Default text inserted into each generated doc block.
          default_message: "Method documentation."

          # Default text appended to generated @param tags.
          param_documentation: "Param documentation."

          # Style for generated @param tags:
          # - type_name => @param [Type] name
          # - name_type => @param name [Type]
          param_tag_style: "type_name"

          # Sort generated / merged tags in safe mode when possible.
          sort_tags: true

          # Tag order used when sorting contiguous tag runs.
          tag_order: ["todo", "note", "api", "private", "protected", "param", "option", "yieldparam", "raise", "return"]

        methods:
          # Per-scope / per-visibility overrides.
          #
          # Example:
          # methods:
          #   instance:
          #     public:
          #       default_message: "Public API."
          #       return_tag: true
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

          # Whether nil unions become optional types (for example String | nil => String?).
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
          # - scopes / visibilities act as allow-lists
          # - exclude wins
          # - if include is empty => include everything (subject to allow-lists)
          visibilities: ["public", "protected", "private"]
          scopes: ["instance", "class"]
          include: []
          exclude: []

          files:
            # Filter which files Docscribe processes (paths are matched relative
            # to the project root).
            #
            # Tips:
            # - Use directory shorthand to exclude a whole directory:
            #     exclude: ["spec"]
            # - Or use globs:
            #     exclude: ["spec/**/*.rb", "vendor/**/*.rb"]
            include: []
            exclude: ["spec"]

        rbs:
          # Optional: use RBS signatures to improve @param / @return types.
          #
          # CLI equivalent:
          # bundle exec docscribe -a --rbs --sig-dir sig lib
          #
          # Under Bundler, you may need `gem "rbs"` in your Gemfile (or a
          # Gemfile that includes it), otherwise `require "rbs"` may fail and
          # Docscribe will fall back to inference.
          enabled: false

          # Signature directories (repeatable via --sig-dir).
          sig_dirs: ["sig"]

          # If true, simplify generic types:
          # - Hash<Symbol, String> => Hash
          # - Array<Integer>       => Array
          collapse_generics: false
          # Auto-discover RBS collection from rbs_collection.lock.yaml.
          # Equivalent to --rbs-collection CLI flag.
          # Requires `bundle exec rbs collection install` to have been run.
          #
          collection: false

        sorbet:
          # Optional: use Sorbet signatures from inline `sig` declarations and
          # RBI files to improve @param / @return types.
          #
          # CLI equivalent:
          # bundle exec docscribe -a --sorbet --rbi-dir sorbet/rbi lib
          #
          # Sorbet resolution order is:
          # 1. inline `sig` in the current source file
          # 2. RBI files
          # 3. RBS
          # 4. AST inference
          enabled: false

          # RBI directories scanned recursively for `.rbi` files
          # (repeatable via --rbi-dir).
          rbi_dirs: ["sorbet/rbi", "rbi"]

          # If true, simplify generic types:
          # - Hash<Symbol, String> => Hash
          # - Array<Integer>       => Array
          collapse_generics: false
      YAML
    end
  end
end
