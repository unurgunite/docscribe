# frozen_string_literal: true

RSpec.describe 'extend self extra behaviors' do
  subject(:out) { inline(code) }

  describe '`extend self, X`' do
    let(:code) do
      <<~RUBY
        module M
          extend self, Kernel
          def foo; 1; end
        end
      RUBY
    end

    it 'treats it as extend-self mode (documents as M.foo)' do
      expect(out).to include('# +M.foo+')
      expect(out).not_to include('# +M#foo+')
      expect(out).not_to include('@note module_function:')
    end
  end

  describe 'private_class_method after extend self' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'visibility_tags' => true }) }

    let(:code) do
      <<~RUBY
        module M
          extend self
          def foo; 1; end
          private_class_method :foo
        end
      RUBY
    end

    it 'endpoint becomes private' do
      expect(out).to include('# +M.foo+')
      expect(out).to match(/# \+M\.foo\+.*?\n.*?# @private/m)
    end
  end

  describe 'persistence across reopened modules' do
    let(:code) do
      <<~RUBY
        module M
          extend self
        end

        module M
          def foo; 1; end
        end
      RUBY
    end

    it 'persists extend self across reopened modules in the same file' do
      expect(out).to include('# +M.foo+')
      expect(out).not_to include('# +M#foo+')
    end
  end
end
