# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  describe 'private after bare private' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
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

    it 'keeps def self.bump public' do
      expect(out).to include('# +Demo.bump+')
    end

    it 'keeps #pub public' do
      expect(out).to include('# +Demo#pub+')
    end

    it 'marks #priv as private' do
      expect(out).to include('# +Demo#priv+').or include('# +Demo#priv+ ')
    end

    it 'marks .internal as private' do
      expect(out).to match(/# \+Demo\.internal\+.*?\n.*?# @private/m)
    end
  end

  describe 'protected instance methods' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
    let(:code) { <<~RUBY }
      class P
      protected
      def prot; end
      def prot2; end

              public
              def pub; end
            end
    RUBY

    it 'includes #prot' do
      expect(out).to include('# +P#prot+')
    end

    it 'includes #prot2' do
      expect(out).to include('# +P#prot2+')
    end

    it 'marks #prot with @protected' do
      expect(out).to match(/# \+P#prot\+.*?\n.*?# @protected/m)
    end

    it 'marks #prot2 with @protected' do
      expect(out).to match(/# \+P#prot2\+.*?\n.*?# @protected/m)
    end

    it 'includes at least one @protected tag' do
      expect(out.scan('@protected').size).to be >= 1
    end

    it 'includes #pub' do
      expect(out).to include('# +P#pub+')
    end
  end
end
