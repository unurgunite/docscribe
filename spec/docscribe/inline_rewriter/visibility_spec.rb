# frozen_string_literal: true

RSpec.describe 'Inline rewriter visibility' do
  describe 'private after bare private' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class Demo
      def pub; end

              private

              def self.bump; :ok; end

              def priv; end

              class << self
                private
                def internal; end
              end
            end
    RUBY

    it 'keeps def self.bump public after a bare private; and marks internal as private' do
      expect(out).to include('# +Demo#pub+')
      expect(out).to include('# +Demo.bump+')
      expect(out).to include('# +Demo#priv+').or include('# +Demo#priv+ ')
      # def internal is a class method under class << self with private => @private
      expect(out).to match(/# \+Demo\.internal\+.*?\n.*?# @private/m)
    end
  end

  describe 'protected instance methods' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class P
      protected
      def prot; end
      def prot2; end

              public
              def pub; end
            end
    RUBY

    it 'marks protected instance methods with @protected' do
      # The inline rewriter adds @protected on the protected methods
      expect(out).to include('# +P#prot+')
      expect(out).to include('# +P#prot2+')
      expect(out).to match(/# \+P#prot\+.*?\n.*?# @protected/m)
      expect(out).to match(/# \+P#prot2\+.*?\n.*?# @protected/m)
      expect(out.scan('@protected').size).to be >= 1
      expect(out).to include('# +P#pub+')
    end
  end
end
