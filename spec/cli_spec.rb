# frozen_string_literal: true

require 'open3'

RSpec.describe 'CLI stingray_docs' do
  it 'reads from --stdin and outputs docs' do
    exe = File.expand_path('../exe/stingray_docs', __dir__)
    code = <<~RUBY
      class D; def x; 1; end; end
    RUBY
    stdout, status = Open3.capture2('ruby', exe, '--stdin', stdin_data: code)
    expect(status.success?).to be true
    expect(stdout).to include('# +D#x+')
  end
end
