# frozen_string_literal: true

require 'parser/current'
require 'docscribe/infer'
require 'docscribe/types/rbs/provider'
require 'docscribe/types/provider_chain'
require 'docscribe/inline_rewriter'
require 'docscribe/config'
require 'docscribe/validator/type_mismatch_validator'

RSpec.describe Docscribe::Infer::Returns do
  describe '.returns_spec_from_node for resolve_rbs_return_type' do
    let(:code) do
      <<~RUBY
        module Docscribe
          module Infer
            module Returns
              def resolve_rbs_return_type(container_type, method_name, core_rbs_provider)
                return FALLBACK_TYPE unless core_rbs_provider

                sig = core_rbs_provider.signature_for(
                  container: container_type,
                  scope: :instance,
                  name: method_name
                )

                sig&.return_type || FALLBACK_TYPE
              end
            end
          end
        end
      RUBY
    end

    let(:ast) { Parser::CurrentRuby.parse(code) }

    def find_def(node, name)
      return nil unless node.is_a?(Parser::AST::Node)
      return node if node.type == :def && node.children[0] == name

      node.children.each do |ch|
        next unless ch.is_a?(Parser::AST::Node)

        res = find_def(ch, name)
        return res if res
      end
      nil
    end

    it 'infers fallback Object without RBS provider (not Object, FALLBACK_TYPE)' do
      node = find_def(ast, :resolve_rbs_return_type)
      spec = described_class.returns_spec_from_node(node, fallback_type: 'Object', nil_as_optional: true, core_rbs_provider: nil)
      expect(spec[:normal]).to eq('Object')
      expect(spec[:normal]).not_to include('FALLBACK_TYPE')
    end

    it 'infers String via RBS when provider available (safe navigation with fallback)' do
      skip_unless_rbs_available!
      provider = Docscribe::Types::RBS::Provider.new(sig_dirs: ['sig'])
      chain = Docscribe::Types::ProviderChain.new(provider)
      node = find_def(ast, :resolve_rbs_return_type)
      param_types = {
        'container_type' => 'String',
        'method_name' => 'String',
        'core_rbs_provider' => 'Docscribe::Types::RBS::Provider'
      }
      spec = described_class.returns_spec_from_node(
        node,
        fallback_type: 'Object',
        nil_as_optional: true,
        core_rbs_provider: provider,
        signature_provider: chain,
        container: 'Docscribe::Infer::Returns',
        param_types: param_types
      )
      # With RBS, sig&.return_type is String? -> unified with fallback via handle_or prefers String?
      expect(spec[:normal]).to eq('String?')
    end

    it 'does not flag YARD String as mismatch for fallback union' do
      validator = Docscribe::Validator::TypeMismatchValidator.new(fallback_type: 'Object')
      expect(validator.mismatched_return?('String', 'Object')).to be false
      expect(validator.mismatched_return?('String', 'Object, FALLBACK_TYPE')).to be false
      expect(validator.mismatched_return?('String', 'String?')).to be false
      expect(validator.mismatched_return?('String', 'String, nil')).to be false
    end

    it 'preserves YARD String for resolve_rbs_return_type with validate_types' do
      yard_code = <<~RUBY
        module Docscribe
          module Infer
            module Returns
              # @return [String]
              def resolve_rbs_return_type(container_type, method_name, core_rbs_provider)
                return FALLBACK_TYPE unless core_rbs_provider
                sig = core_rbs_provider.signature_for(container: container_type, scope: :instance, name: method_name)
                sig&.return_type || FALLBACK_TYPE
              end
            end
          end
        end
      RUBY
      config = Docscribe::Config.new('validate_types' => true)
      out = Docscribe::InlineRewriter.insert_comments(yard_code, strategy: :safe, config: config)
      # Should not rewrite String to Object
      expect(out).to include('@return [String]')
      expect(out).not_to include('Object, FALLBACK_TYPE')
      report = Docscribe::InlineRewriter.rewrite_with_report(yard_code, strategy: :safe, config: config)
      updated = report[:changes].select { |c| c[:type] == :updated_return }
      expect(updated).to be_empty
    end
  end
end
