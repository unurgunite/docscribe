# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  describe 'merges into existing doc block' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        module M
          module_function

          # @todo keep this
          # @return [String] already documented
          def foo(x)
            "ok"
          end
        end
      RUBY
    end

    it 'preserves existing doc lines', :aggregate_failures do
      expect(out).to include('# @todo keep this')
      expect(out).to include('# @return [String] already documented')
    end

    it 'merges added note and param', :aggregate_failures do
      expect(out).to include('# @note module_function:')
      expect(out).to include(param_tag('x', 'Object'))
    end

    it 'does not introduce extra blank lines between @note and @param', :aggregate_failures do
      expect(out).to match(/@note module_function:.*\n\s*# @param/m)
      expect(out).not_to match(/@note module_function:.*\n\s*\n\s*# @param/m)
    end
  end
end
