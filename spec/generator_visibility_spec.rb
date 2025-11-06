# frozen_string_literal: true

RSpec.describe 'Generator visibility grouping' do
  def generate(code)
    StingrayDocsInternal::Generator.generate_documentation(code)
  end

  it 'keeps def self.bump public after a bare private; and groups private instance methods' do
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

    out = generate(code)

    # public method header
    expect(out).to include('# +Demo#pub+')
    # singleton def after bare private stays public
    expect(out).to include('# +Demo.bump+')

    # private section exists and contains private instance and private class methods
    expect(out).to include('# private')
    expect(out).to include('# +Demo#priv+')
    expect(out).to include('# +Demo.internal+')
  end

  it 'groups protected methods under a protected section' do
    code = <<~RUBY
      class P
      protected
      def prot; end
      def prot2; end

              public
              def pub; end
            end
    RUBY

    out = generate(code)
    expect(out).to include('# protected')
    expect(out).to include('# +P#prot+')
    expect(out).to include('# +P#prot2+')
    expect(out).to include('# +P#pub+')
  end
end
