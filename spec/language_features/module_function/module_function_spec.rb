# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  describe '`module_function` (no args)' do
    let(:code) do
      <<~RUBY
        module M
          module_function
          def foo; 1; end
        end
      RUBY
    end

    it 'documents methods as module methods', :aggregate_failures do
      expect(out).to include('# +M.foo+')
      expect(out).to include('# @return [Integer]')
    end
  end

  describe '`module_function :foo`' do
    let(:code) do
      <<~RUBY
        module M
          def foo; 1; end
          def bar; 2; end
          module_function :foo
        end
      RUBY
    end

    it 'retroactively documents as a module method', :aggregate_failures do
      expect(out).to include('# +M.foo+')
      expect(out).to include('# +M#bar+')
    end
  end

  describe '`module_function :foo, :bar`' do
    let(:code) do
      <<~RUBY
        module M
          def foo; 1; end
          def bar; 2; end
          module_function :foo, :bar
        end
      RUBY
    end

    it 'handles multiple names', :aggregate_failures do
      expect(out).to include('# +M.foo+')
      expect(out).to include('# +M.bar+')
    end
  end
end
