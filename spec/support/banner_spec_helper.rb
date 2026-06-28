# frozen_string_literal: true

module BannerSpecHelper
  NAME_MAP = {
    'server' => 'ServerCmd'
  }.freeze

  def self.module_name(file)
    bn = File.basename(file, '.rb')
    mapped = NAME_MAP[bn] || bn.split('_').map(&:capitalize).join
    "Docscribe::CLI::#{mapped}"
  end
end
