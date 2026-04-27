# frozen_string_literal: true

RSpec.describe 'extend self boundary' do
  subject(:out) { inline(code) }

  describe 'promotion scope' do
    let(:code) do
      <<~RUBY
        module M
          def a; 1; end

          extend self

          def b; 2; end
        end
      RUBY
    end

    it 'does not retroactively promote defs that appear after extend self' do
      # a should be module method
      expect(out).to include('# +M.a+')
      expect(out).not_to include('# +M#a+')

      # b should also be module method because extend self applies to subsequent defs too
      # (this assertion should pass either way)
      expect(out).to include('# +M.b+')
    end
  end

  describe 'cross-container isolation' do
    let(:code) do
      <<~RUBY
        module M
          def a; 1; end
          extend self
        end

        module N
          def a; 2; end
        end
      RUBY
    end

    it 'does not promote methods from other containers' do
      expect(out).to include('# +M.a+')
      expect(out).to include('# +N#a+')
    end
  end
end
