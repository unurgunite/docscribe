# frozen_string_literal: true

RSpec.describe 'extend self handling' do
  subject(:out) { inline(code) }

  describe 'methods after `extend self`' do
    let(:code) do
      <<~RUBY
        module M
          extend self

          def foo(x)
            x
          end
        end
      RUBY
    end

    it 'documents methods as module methods (M.foo)' do
      expect(out).to include('# +M.foo+')
      expect(out).to include(param_tag('x', 'Object'))
      expect(out).not_to include('# +M#foo+')
      expect(out).not_to include('@note module_function:')
    end
  end

  describe 'retroactive promotion' do
    let(:code) do
      <<~RUBY
        module M
          def foo; 1; end
          extend self
        end
      RUBY
    end

    it 'promotes earlier defs when `extend self` appears after them' do
      expect(out).to include('# +M.foo+')
      expect(out).not_to include('# +M#foo+')
      expect(out).not_to include('@note module_function:')
    end
  end

  describe 'visibility handling' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'visibility_tags' => true }) }
    let(:code) do
      <<~RUBY
        module M
          extend self
          private
          def secret; 1; end
        end
      RUBY
    end

    it 'private methods become private module methods too' do
      expect(out).to include('# +M.secret+')
      expect(out).to match(/# \+M\.secret\+.*?\n.*?# @private/m)
    end
  end
end
