# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS core types in Docscribe' do
  subject(:out) { inline(code, config: config) }

  let(:config) do
    Docscribe::Config.new(
      'rbs' => { 'enabled' => true, 'sig_dirs' => [] },
      'emit' => { 'header' => true, 'return_tags' => true }
    )
  end

  describe 'when using RBS core types' do
    describe 'infers Boolean for arg.positive?' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo(arg = 1)
              arg.positive?
            end
          end
        RUBY
      end

      it do
        skip_unless_rbs_available!

        # With core RBS, positive? returns bool.
        expect(out).to include('# @return [Boolean]')
        expect(out).not_to include('# @return [Object]')
      end

      describe 'when infers Integer for arg.to_i' do
        let(:code) do
          <<~RUBY
            class Demo
              def foo(arg = '')
                arg.to_i
              end
            end
          RUBY
        end

        it do
          skip_unless_rbs_available!

          expect(out).to include('# @return [Integer]')
          expect(out).not_to include('# @return [Object]')
        end
      end

      describe 'infers Integer for chained call arg.to_s.length' do
        let(:code) do
          <<~RUBY
            class Demo
              def foo(arg = 1)
                arg.to_s.length
              end
            end
          RUBY
        end

        it do
          skip_unless_rbs_available!

          expect(out).to include('# @return [Integer]')
          expect(out).not_to include('# @return [Object]')
        end
      end

      describe 'infers String for arg.upcase' do
        let(:code) do
          <<~RUBY
            class Demo
              def foo(arg = "")
                arg.upcase
              end
            end
          RUBY
        end

        it do
          skip_unless_rbs_available!
          expect(out).to include('# @return [String]')
          expect(out).not_to include('# @return [Object]')
        end
      end

      describe 'infers String for rescue branch' do
        let(:code) do
          <<~RUBY
            class Demo
              def foo(arg = "")
                arg.upcase
              rescue
                "default"
              end
            end
          RUBY
        end

        it do
          skip_unless_rbs_available!

          expect(out).to include('# @return [String]')
        end
      end
    end
  end
end
