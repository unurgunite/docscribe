# frozen_string_literal: true

RSpec.describe 'module_function documentation note' do
  subject(:out) { inline(code) }

  describe 'default instance visibility' do
    let(:code) do
      <<~RUBY
        module M
          module_function
          def foo; 1; end
        end
      RUBY
    end

    it 'notes included instance visibility is private by default' do
      expect(out).to include('# @note module_function: when included, also defines #foo (instance visibility: private)')
      expect(out).to include('# +M.foo+')
    end
  end

  describe 'overridden instance visibility' do
    let(:code) do
      <<~RUBY
        module M
          module_function
          public def foo; 1; end
        end
      RUBY
    end

    it 'notes included instance visibility can be overridden with public def' do
      expect(out).to include('# @note module_function: when included, also defines #foo (instance visibility: public)')
      expect(out).to include('# +M.foo+')
    end
  end
end
