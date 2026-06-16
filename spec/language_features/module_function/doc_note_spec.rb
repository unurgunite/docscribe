# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  describe 'default instance visibility' do
    let(:code) do
      <<~RUBY
        module M
          module_function
          def foo; 1; end
        end
      RUBY
    end

    it 'notes included instance visibility is private by default', :aggregate_failures do
      expect(out).to include('# @note module_function: defines #foo (visibility: private)')
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

    it 'notes included instance visibility can be overridden with public def', :aggregate_failures do
      expect(out).to include('# @note module_function: defines #foo (visibility: public)')
      expect(out).to include('# +M.foo+')
    end
  end
end
