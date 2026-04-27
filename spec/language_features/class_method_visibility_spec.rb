# frozen_string_literal: true

RSpec.describe 'class method visibility helpers' do
  let(:conf) { Docscribe::Config.new('emit' => { 'visibility_tags' => true }) }

  describe 'private_class_method' do
    subject(:out) { inline(code, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          def self.foo; 1; end
          private_class_method :foo
        end
      RUBY
    end

    it 'marks def self.foo as private when private_class_method :foo appears after the def' do
      expect(out).to include('# +A.foo+ -> Integer')
      expect(out).to include('# @private')
    end
  end

  describe 'protected_class_method' do
    subject(:out) { inline(code, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          def self.foo; 1; end
          protected_class_method :foo
        end
      RUBY
    end

    it 'marks def self.foo as protected when protected_class_method :foo appears after the def' do
      expect(out).to include('# +A.foo+ -> Integer')
      expect(out).to include('# @protected')
    end
  end

  describe 'public_class_method' do
    subject(:out) { inline(code, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          class << self
            private
            def foo; 1; end
          end

          public_class_method :foo
        end
      RUBY
    end

    it 'can make a class method public again via public_class_method :foo' do
      expect(out).to include('# +A.foo+ -> Integer')
      expect(out).not_to match(/# \+A\.foo\+.*?\n.*?# @private/m)
    end
  end
end
