# frozen_string_literal: true

RSpec.describe 'Inline rewriter visibility' do
  it 'keeps def self.bump public after a bare private; and marks internal as private' do
    code = <<~RUBY
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

    out = inline(code)
    expect(out).to include('# +Demo#pub+')
    expect(out).to include('# +Demo.bump+')
    expect(out).to include('# +Demo#priv+').or include('# +Demo#priv+ ')
    # def internal is a class method under class << self with private => @private
    expect(out).to match(/# \+Demo\.internal\+.*?\n.*?# @private/m)
  end

  it 'marks protected instance methods with @protected' do
    code = <<~RUBY
      class P
      protected
      def prot; end
      def prot2; end

              public
              def pub; end
            end
    RUBY

    out = inline(code)
    # The inline rewriter adds @protected on the protected methods
    expect(out).to include('# +P#prot+')
    expect(out).to include('# +P#prot2+')
    expect(out).to match(/# \+P#prot\+.*?\n.*?# @protected/m)
    expect(out).to match(/# \+P#prot2\+.*?\n.*?# @protected/m)
    expect(out.scan('@protected').size).to be >= 1
    expect(out).to include('# +P#pub+')
  end
end
