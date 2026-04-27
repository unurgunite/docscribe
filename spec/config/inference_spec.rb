# frozen_string_literal: true

RSpec.describe 'Inference config' do
  describe 'fallback_type' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('inference' => { 'fallback_type' => 'Any' }) }

    let(:code) do
      <<~RUBY
        class A
          def foo
            something_dynamic
          end
        end
      RUBY
    end

    it 'respects inference.fallback_type for unknown return types' do
      expect(out).to include('# +A#foo+ -> Any')
      expect(out).to include('# @return [Any]')
    end
  end

  describe 'nil_as_optional' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('inference' => { 'nil_as_optional' => false }) }

    let(:code) do
      <<~RUBY
        class A
          def foo(x)
            if x
              "a"
            else
              nil
            end
          end
        end
      RUBY
    end

    it 'respects inference.nil_as_optional=false (uses union instead of ?)' do
      expect(out).to include('# +A#foo+ -> String, nil')
      expect(out).to include('# @return [String, nil]')
    end
  end

  describe 'treat_options_keyword_as_hash' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('inference' => { 'treat_options_keyword_as_hash' => false }) }

    let(:code) do
      <<~RUBY
        class A
          def foo(options:)
            1
          end
        end
      RUBY
    end

    it 'respects inference.treat_options_keyword_as_hash=false' do
      expect(out).to include(param_tag('options', 'Object'))
    end
  end
end
