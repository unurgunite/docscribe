# frozen_string_literal: true

RSpec.describe StingrayDocsInternal do
  it 'has a version number' do
    expect(StingrayDocsInternal::VERSION).not_to be nil
  end

  it 'generates doc for class with one method' do
    code = <<~CODE
      class A
      def abc
      return 123
      end
      end
    CODE

    out = StingrayDocsInternal::Generator.generate_documentation(code)

    # Header and return type (inferred Integer)
    expect(out).to include('# +A#abc+')
    expect(out).to match(/\# \+A\#abc\+\s*-> Integer/)
    expect(out).to include('@return [Integer]')

    # Source lines are present
    expect(out).to include('def abc')
    expect(out).to include('return 123')
    expect(out).to include('end')
  end

  it 'generates doc for class with multiple methods' do
    code = <<~CODE
      class A
      def foo
      return 123
      end


          def bar
            return 123
          end

          def buzz
            return 123
          end
        end
    CODE

    out = StingrayDocsInternal::Generator.generate_documentation(code)

    %w[foo bar buzz].each do |m|
      expect(out).to include("# +A##{m}+")
      expect(out).to match(/\# \+A\##{m}\+\s*-> Integer/)
      expect(out).to include('@return [Integer]')
    end
  end
end
