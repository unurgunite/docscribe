# frozen_string_literal: true

require 'English'
require 'optparse'
require 'fileutils'
require 'docscribe/parsing'
require 'docscribe/types/yard/parser'
require 'docscribe/types/yard/formatter'

module Docscribe
  module CLI
    module RbsGen
      BANNER = <<~TEXT
        Usage: docscribe rbs [options] [files...]

        Generate RBS signature files from YARD documentation.

      TEXT

      YardTags = Data.define(:params, :return_type, :options)
      ParamTag = Data.define(:name, :type)
      MethodDef = Data.define(:name, :scope, :container, :file, :line, :yard_tags)

      class << self
        # @param [Object] argv
        # @return [Integer]
        def run(argv)
          options = parse_options(argv)
          paths = expand_paths(argv)
          return no_files_found if paths.empty?

          run_with(options, paths)
        end

        private

        # @private
        # @param [Object] argv
        # @return [Hash<Symbol, Object>]
        def parse_options(argv)
          options = { output_dir: 'sig', dry_run: false, force: false }

          OptionParser.new do |opts|
            opts.banner = BANNER
            opts.on('-o', '--output DIR', 'Output directory (default: sig)') { |d| options[:output_dir] = d }
            opts.on('-n', '--dry-run', 'Print generated RBS to stdout') { options[:dry_run] = true }
            opts.on('-f', '--force', 'Overwrite existing files') { options[:force] = true }
            opts.on('-h', '--help', 'Show this help') do
              puts opts
              exit 0
            end
          end.parse!(argv)

          options
        end

        # @private
        # @param [Object] args
        # @return [Array<String>]
        def expand_paths(args)
          files = [] #: Array[String]
          args = ['.'] if args.empty?
          args.each { |path| expand_single_path(files, path) }
          files.uniq.sort
        end

        # @private
        # @param [Object] files
        # @param [Object] path
        # @return [void]
        def expand_single_path(files, path)
          if File.directory?(path)
            files.concat(Dir.glob(File.join(path, '**', '*.rb')))
          elsif File.file?(path)
            files << path
          else
            warn "Skipping missing path: #{path}"
          end
        end

        # @private
        # @return [Integer]
        def no_files_found
          warn 'No files found. Pass files or directories (e.g. `docscribe rbs lib`).'
          2
        end

        # @private
        # @param [Object] options
        # @param [Object] paths
        # @return [Integer]
        def run_with(options, paths)
          errors = 0
          paths.each do |path|
            generate_for_file(path, options) or (errors += 1)
          end
          errors.zero? ? 0 : 1
        end

        # @private
        # @param [Object] path
        # @param [Object] options
        # @raise [Parser::SyntaxError]
        # @raise [StandardError]
        # @return [Boolean] if StandardError
        # @return [Boolean] if Parser::SyntaxError
        # @return [Boolean] if StandardError
        def generate_for_file(path, options)
          src = File.read(path)
          src_lines = src.lines
          result = Docscribe::Parsing.parse_with_comments(src, file: path)
          return false unless result

          ast, comments = result
          comment_map = build_comment_map(comments)
          method_defs = [] #: Array[MethodDef]
          walk_for_methods(ast, [], method_defs, path, comment_map, src_lines)
          return true if method_defs.empty?

          rbs_content = build_rbs_content(method_defs)
          return false unless rbs_content

          if options[:dry_run]
            puts rbs_content
          else
            write_file(rbs_content, path, options)
          end
          true
        rescue Parser::SyntaxError # steep:ignore
          warn "Syntax error in #{path}: #{$ERROR_INFO.message}"
          false
        rescue StandardError
          warn "Error processing #{path}: #{$ERROR_INFO.class}: #{$ERROR_INFO.message}"
          false
        end

        # @private
        # @param [Object] comments
        # @return [Hash<Integer, String>]
        def build_comment_map(comments)
          map = {} #: Hash[Integer, String]
          return map unless comments

          comments.each do |comment|
            map[comment.location.line] = comment.text
          end
          map
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @param [Boolean] inside_sclass
        # @return [void]
        def walk_for_methods(node, containers, methods, path, comment_map, src_lines, inside_sclass: false)
          return unless node.is_a?(Parser::AST::Node)

          case node.type
          when :class, :module then walk_class_module(node, containers, methods, path, comment_map, src_lines)
          when :sclass then walk_sclass(node, containers, methods, path, comment_map, src_lines)
          when :def then collect_def(node, containers, methods, path, comment_map, src_lines,
                                     inside_sclass: inside_sclass)
          when :defs then collect_defs(node, containers, methods, path, comment_map, src_lines)
          else walk_children(node, containers, methods, path, comment_map, src_lines, inside_sclass: inside_sclass)
          end
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @return [void]
        def walk_class_module(node, containers, methods, path, comment_map, src_lines)
          containers.push(const_name(node.children[0]))
          node.children.drop(1).each { |c| walk_for_methods(c, containers, methods, path, comment_map, src_lines) }
          containers.pop
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @return [void]
        def walk_sclass(node, containers, methods, path, comment_map, src_lines)
          node.children.drop(1).each do |c|
            walk_for_methods(c, containers, methods, path, comment_map, src_lines, inside_sclass: true)
          end
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @param [Boolean] inside_sclass
        # @return [void]
        def walk_children(node, containers, methods, path, comment_map, src_lines, inside_sclass: false)
          node.children.each do |c|
            walk_for_methods(c, containers, methods, path, comment_map, src_lines, inside_sclass: inside_sclass)
          end
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @param [Boolean] inside_sclass
        # @return [void]
        def collect_def(node, containers, methods, path, comment_map, src_lines, inside_sclass: false)
          line = node.loc&.line || 1
          yard_block = find_yard_block(line, comment_map, src_lines)
          yard_tags = yard_block.any? ? parse_yard_tags(yard_block) : nil

          methods << MethodDef.new(
            name: node.children[0],
            scope: inside_sclass ? :class : :instance,
            container: container_name(containers),
            file: path,
            line: line,
            yard_tags: yard_tags
          )
        end

        # @private
        # @param [Object] node
        # @param [Object] containers
        # @param [Object] methods
        # @param [Object] path
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @return [void]
        def collect_defs(node, containers, methods, path, comment_map, src_lines)
          line = node.loc&.line || 1
          yard_block = find_yard_block(line, comment_map, src_lines)
          yard_tags = yard_block.any? ? parse_yard_tags(yard_block) : nil

          methods << MethodDef.new(
            name: node.children[1],
            scope: :class,
            container: container_name(containers),
            file: path,
            line: line,
            yard_tags: yard_tags
          )
        end

        # @private
        # @param [Object] line
        # @param [Object] comment_map
        # @param [Object] src_lines
        # @return [Array<String>]
        def find_yard_block(line, comment_map, src_lines)
          block = [] #: Array[String]
          idx = line - 2
          while idx >= 0
            src_line = src_lines[idx]&.strip
            break if src_line.nil? || src_line.empty?

            if comment_map.key?(idx + 1)
              block.unshift(comment_map[idx + 1])
              idx -= 1
            elsif block.empty?
              idx -= 1
            else
              break
            end
          end
          block
        end

        # @private
        # @param [Object] comment_lines
        # @return [Docscribe::CLI::RbsGen::YardTags]
        def parse_yard_tags(comment_lines)
          params = [] #: Array[ParamTag]
          options = [] #: Array[ParamTag]
          return_type = nil

          comment_lines.each do |line|
            text = line.sub(/\A#\s*/, '')
            case text
            when /\A@param\s+\[([^\]]+)\]\s+(\S+)\s*/
              params << ParamTag.new(name: ::Regexp.last_match(2), type: ::Regexp.last_match(1))
            when /\A@param\s+(\S+)\s+\[([^\]]+)\]\s*/
              params << ParamTag.new(name: ::Regexp.last_match(1), type: ::Regexp.last_match(2))
            when /\A@option\s+\S+\s+\[([^\]]+)\]\s+:?(\S+)\s*/
              options << ParamTag.new(name: ::Regexp.last_match(2), type: ::Regexp.last_match(1))
            when /\A@return\s+\[([^\]]+)\]\s*/
              return_type = ::Regexp.last_match(1)
            end
          end

          YardTags.new(params: params, return_type: return_type, options: options)
        end

        # @private
        # @param [Object] containers
        # @return [String?]
        def container_name(containers)
          containers.empty? ? nil : containers.join('::')
        end

        # @private
        # @param [Object] node
        # @return [String]
        def const_name(node)
          return node.to_s unless node.is_a?(Parser::AST::Node)
          return node.children[1].to_s if node.type == :const

          node.children.map { |c| c.is_a?(Parser::AST::Node) ? const_name(c) : c.to_s }.join('::')
        end

        # @private
        # @param [Object] method_defs
        # @return [String]
        def build_rbs_content(method_defs)
          grouped = method_defs.group_by { |m| m.container || '' }

          lines = [] #: Array[String]
          grouped.each do |container, methods|
            lines << '' unless lines.empty?
            if container.empty?
              methods.each { |m| lines << format_method_sig(m) }
            else
              lines << "class #{container}"
              methods.each { |m| lines << "  #{format_method_sig(m)}" }
              lines << 'end'
            end
          end

          "#{lines.join("\n")}\n"
        end

        # @private
        # @param [Object] method
        # @return [String]
        def format_method_sig(method)
          prefix = method.scope == :class ? 'self.' : ''
          ret = method.yard_tags&.return_type ? type_to_rbs(method.yard_tags.return_type) : 'untyped'
          params = method.yard_tags&.params || []
          options = method.yard_tags&.options || []

          param_strs = params.map { |p| "#{type_to_rbs(p.type)} #{p.name}" }
          options.each { |o| param_strs << "?#{type_to_rbs(o.type)} #{o.name}" }

          if param_strs.any?
            "def #{prefix}#{method.name}: (#{param_strs.join(', ')}) -> #{ret}"
          else
            "def #{prefix}#{method.name}: () -> #{ret}"
          end
        end

        # @private
        # @param [Object] yard_type
        # @return [String]
        def type_to_rbs(yard_type)
          ast = Docscribe::Types::Yard.parse(yard_type)
          Docscribe::Types::Yard::Formatter.to_rbs(ast)
        end

        # @private
        # @param [Object] content
        # @param [Object] source_path
        # @param [Object] options
        # @return [void]
        def write_file(content, source_path, options)
          abs = File.expand_path(source_path)
          pwd = File.expand_path(Dir.pwd)
          rel = abs.start_with?(pwd) ? abs.sub("#{pwd}/", '') : File.basename(abs)
          rbs_path = rel.sub(/\.rb\z/, '.rbs')
          out_path = File.join(options[:output_dir], rbs_path)
          dir = File.dirname(out_path)

          if File.exist?(out_path) && !options[:force]
            warn "Skipping #{out_path} (use --force to overwrite)"
            return
          end

          FileUtils.mkdir_p(dir)
          File.write(out_path, content)
          puts "Generated #{out_path}"
        end
      end
    end
  end
end
