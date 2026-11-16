# frozen_string_literal: true

require 'docscribe/inline_rewriter'

RSpec.describe Docscribe::InlineRewriter do
  def rewrite(code, **options)
    described_class.rewrite_with_report(code, **options)[:output]
  end

  def with_param(type, body)
    <<~RUBY
      class Example
        # @param [#{type}] counts counts the things
        def tally(counts)
          #{body}
        end
      end
    RUBY
  end

  let(:provider) { Docscribe::Types::RBS::Provider.new(sig_dirs: []) }

  before do
    skip_unless_rbs_available!
    require 'docscribe/types/rbs/provider'
  end

  context 'with a declared @param type that inference cannot recover' do
    it 'seeds the declared type so the chain keeps its element type' do
      output = rewrite(with_param('Hash<String, Integer>', 'counts.each_with_index.to_h'),
                       config: Docscribe::Config.new(validate_types: false), core_rbs_provider: provider)

      expect(output).to include('@return [Hash<String, Integer>]')
    end

    it 'collapses to Object without the declared type' do
      output = rewrite(<<~RUBY, config: Docscribe::Config.new(validate_types: false), core_rbs_provider: provider)
        class Example
          def tally(counts)
            counts.each_with_index.to_h
          end
        end
      RUBY

      expect(output).to include('@return [Hash<Object, Integer>]')
    end
  end

  context 'when the declared type is more precise than the inferred base' do
    it 'keeps the declared generic detail' do
      output = rewrite(with_param('Array<String>', 'return counts.first unless counts.empty?'),
                       config: Docscribe::Config.new(validate_types: false), core_rbs_provider: provider)

      expect(output).to include('@param [Array<String>] counts')
    end
  end

  context 'with invalid YARD syntax in a declared @param' do
    it 'repairs the broken type instead of seeding it' do
      source = <<~RUBY
        class Example
          # @param [Sym bol] counts counts the things
          def tally(counts)
            counts.size
          end
        end
      RUBY

      output = rewrite(source, config: Docscribe::Config.new(validate_types: false), core_rbs_provider: provider)
      expect(output).to include('@param [Symbol] counts')
    end
  end

  context 'when validate_types is enabled (the default)' do
    it 'does not seed declared types, so mismatches stay reportable' do
      output = rewrite(with_param('Hash<String, Integer>', 'counts.each_with_index.to_h'),
                       config: Docscribe::Config.new, core_rbs_provider: provider)

      expect(output).to include('@param [Hash<String, Integer>] counts')
      expect(output).not_to include('@return [Hash<String, Integer>]')
    end
  end

  context 'with aggressive mode' do
    it 'does not seed declared types over re-inferred ones' do
      output = rewrite(with_param('Hash<String, Integer>', 'counts.each_with_index.to_h'),
                       strategy: :aggressive, config: Docscribe::Config.new(keep_descriptions: true, validate_types: false),
                       core_rbs_provider: provider)

      expect(output).not_to include('@return [Hash<String, Integer>]')
    end
  end
end
