# frozen_string_literal: true

RSpec.describe 'class method visibility helpers' do
  it 'marks def self.foo as private when private_class_method :foo appears after the def' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      class A
        def self.foo; 1; end
        private_class_method :foo
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to include('# +A.foo+')
    expect(out).to match(/# \+A\.foo\+.*?\n.*?# @private/m)
  end

  it 'marks def self.foo as protected when protected_class_method :foo appears after the def' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      class A
        def self.foo; 1; end
        protected_class_method :foo
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to include('# +A.foo+')
    expect(out).to match(/# \+A\.foo\+.*?\n.*?# @protected/m)
  end

  it 'can make a class method public again via public_class_method :foo' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      class A
        class << self
          private
          def foo; 1; end
        end

        public_class_method :foo
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to include('# +A.foo+')
    expect(out).not_to match(/# \+A\.foo\+.*?\n.*?# @private/m)
  end
end
