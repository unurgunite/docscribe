# frozen_string_literal: true

RSpec.describe 'RBS Ruby version compatibility' do
  describe 'core_rbs_provider' do
    it 'returns nil on Ruby < 3.0' do
      stub_const('RUBY_VERSION', '2.7.8')

      config = Docscribe::Config.new({})
      expect(config.core_rbs_provider).to be_nil
    end

    it 'warns when Ruby < 3.0' do
      stub_const('RUBY_VERSION', '2.7.8')

      config = Docscribe::Config.new({})
      expect { config.core_rbs_provider }
        .to output(/RBS requires Ruby 3\.0\+/).to_stderr
    end
  end
end
