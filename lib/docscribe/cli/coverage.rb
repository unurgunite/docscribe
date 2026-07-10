# frozen_string_literal: true

require 'optparse'
require 'docscribe/config'
require 'docscribe/cli/config_builder'
require 'docscribe/cli/options'

module Docscribe
  module CLI
    module Coverage
      BANNER = <<~TEXT
        Usage: docscribe coverage [options] [paths]

        Generate documentation coverage report.

        Options:
      TEXT

      CoverageStats = Struct.new(
        :total_methods, :documented_methods,
        :total_params, :documented_params,
        :total_returns, :documented_returns,
        keyword_init: true
      ) do
        def method_coverage
          total_methods.zero? ? 100.0 : (documented_methods.to_f / total_methods * 100).round(1)
        end

        def param_coverage
          total_params.zero? ? 100.0 : (documented_params.to_f / total_params * 100).round(1)
        end

        def return_coverage
          total_returns.zero? ? 100.0 : (documented_returns.to_f / total_returns * 100).round(1)
        end
      end

      class << self
        def run(argv)
          opts = parse_options(argv)
          return 0 if opts[:help]

          conf = Docscribe::Config.load(opts[:config])
          paths = expand_paths(argv, conf)

          stats = analyze_coverage(paths, conf)

          print_report(stats, opts)
          0
        end

        private

        def parse_options(argv)
          opts = { config: nil, format: 'text' }
          parser = OptionParser.new do |o|
            o.banner = BANNER
            o.on('--config PATH', 'Path to config file') { |v| opts[:config] = v }
            o.on('--format FORMAT', 'Output format (text, json)') { |v| opts[:format] = v }
            o.on('-h', '--help', 'Show help') { opts[:help] = true; puts o }
          end
          parser.parse!(argv)
          opts
        end

        def expand_paths(argv, conf)
          require 'pathname'
          args = argv.empty? ? ['.'] : argv
          files = []
          args.each do |path|
            if File.directory?(path)
              files.concat(Dir.glob(File.join(path, '**', '*.rb')))
            elsif File.file?(path)
              files << path
            end
          end
          files.uniq.sort.select { |p| conf.process_file?(p) }
        end

        def analyze_coverage(paths, conf)
          require 'docscribe/parsing'
          require 'parser/current'

          stats = CoverageStats.new(
            total_methods: 0, documented_methods: 0,
            total_params: 0, documented_params: 0,
            total_returns: 0, documented_returns: 0
          )

          paths.each do |path|
            src = File.read(path)
            buffer = Parser::Source::Buffer.new(path, source: src)
            ast = Docscribe::Parsing.parse_buffer(buffer)
            next unless ast

            analyze_node(ast, stats, src)
          rescue StandardError
          end

          stats
        end

        def analyze_node(node, stats, src)
          return unless node.is_a?(Parser::AST::Node)

          if %i[def defs].include?(node.type)
            stats.total_methods += 1
            line = node.loc.expression.line
            doc_comment = extract_doc_comment(src, line)

            if doc_comment
              stats.documented_methods += 1

              if doc_comment.match?(/@return\b/)
                stats.documented_returns += 1
              end
              stats.total_returns += 1

              param_matches = doc_comment.scan(/@param\b/)
              args_node = node.children[2] || node.children[1]
              if args_node.is_a?(Parser::AST::Node) && args_node.type == :args
                param_count = args_node.children.count { |a| %i[arg optarg kwarg kwoptarg restarg].include?(a.type) }
                stats.total_params += param_count
                stats.documented_params += [param_matches.size, param_count].min
              end
            else
              stats.total_returns += 1
              args_node = node.children[2] || node.children[1]
              if args_node.is_a?(Parser::AST::Node) && args_node.type == :args
                stats.total_params += args_node.children.count { |a| %i[arg optarg kwarg kwoptarg restarg].include?(a.type) }
              end
            end
          end

          node.children.each { |child| analyze_node(child, stats, src) if child.is_a?(Parser::AST::Node) }
        end

        def extract_doc_comment(src, method_line)
          lines = src.lines
          comment_lines = []
          idx = method_line - 2

          while idx >= 0
            line = lines[idx]
            break unless line =~ /^\s*#/
            comment_lines.unshift(line)
            idx -= 1
          end

          return nil if comment_lines.empty?
          comment_lines.join
        end

        def print_report(stats, opts)
          case opts[:format]
          when 'json'
            require 'json'
            puts JSON.pretty_generate(
              methods: { total: stats.total_methods, documented: stats.documented_methods, coverage: stats.method_coverage },
              params: { total: stats.total_params, documented: stats.documented_params, coverage: stats.param_coverage },
              returns: { total: stats.total_returns, documented: stats.documented_returns, coverage: stats.return_coverage }
            )
          else
            puts "Documentation Coverage Report"
            puts "============================="
            puts
            puts "Methods: #{stats.documented_methods}/#{stats.total_methods} (#{stats.method_coverage}%)"
            puts "Params:  #{stats.documented_params}/#{stats.total_params} (#{stats.param_coverage}%)"
            puts "Returns: #{stats.documented_returns}/#{stats.total_returns} (#{stats.return_coverage}%)"
          end
        end
      end
    end
  end
end
