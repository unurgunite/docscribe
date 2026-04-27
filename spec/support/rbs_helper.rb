# frozen_string_literal: true

module RbsHelper
  # Rewrite +code+ with Sorbet integration enabled.
  #
  # @param [String] code Ruby source to rewrite
  # @param [Symbol] strategy :safe or :aggressive
  # @param [Hash] config_overrides additional raw config keys merged on top
  # @return [String] rewritten source
  def inline_with_sorbet(code, strategy: :safe, config_overrides: {})
    skip_unless_sorbet_bridge_available!

    raw = {
      'sorbet' => {
        'enabled' => true
      }
    }.merge(config_overrides)

    inline(
      code,
      strategy: strategy,
      config: Docscribe::Config.new(raw)
    )
  end

  # Rewrite +code+ with both Sorbet RBI and optionally RBS signature files.
  #
  # Creates a temporary directory, writes the provided signature content to
  # files inside it, builds a config from those paths, and rewrites +code+.
  #
  # @param [String] code Ruby source to rewrite
  # @param [String] rbi RBI file content
  # @param [String, nil] rbs RBS file content (optional)
  # @param [String] rbi_dir_name relative path for the RBI directory
  # @param [String] sig_dir_name relative path for the RBS sig directory
  # @return [String] rewritten source
  def inline_with_signature_files(code:, rbi:, rbs: nil, rbi_dir_name: 'sorbet/rbi', sig_dir_name: 'sig')
    skip_unless_sorbet_bridge_available!

    Dir.mktmpdir do |dir|
      rbi_dir = File.join(dir, rbi_dir_name)
      FileUtils.mkdir_p(rbi_dir)
      File.write(File.join(rbi_dir, 'demo.rbi'), rbi)

      raw = {
        'sorbet' => {
          'enabled' => true,
          'rbi_dirs' => [rbi_dir]
        }
      }

      if rbs
        sig_dir = File.join(dir, sig_dir_name)
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        raw['rbs'] = {
          'enabled' => true,
          'sig_dirs' => [sig_dir]
        }
      end

      inline(
        code,
        config: Docscribe::Config.new(raw)
      )
    end
  end

  # Rewrite +code+ with RBS integration enabled.
  #
  # Creates a temporary directory, writes the provided RBS content to a file
  # inside it, builds a config from that path, and rewrites +code+.
  #
  # @param [String] code Ruby source to rewrite
  # @param [String] rbs RBS file content
  # @param [String] sig_dir_name relative path for the sig directory
  # @return [String] rewritten source
  def inline_with_rbs(code:, rbs:, sig_dir_name: 'sig')
    skip_unless_rbs_available!

    Dir.mktmpdir do |dir|
      sig_dir = File.join(dir, sig_dir_name)
      FileUtils.mkdir_p(sig_dir)
      File.write(File.join(sig_dir, 'demo.rbs'), rbs)

      inline(
        code,
        config: Docscribe::Config.new(
          'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
        )
      )
    end
  end

  private

  # Skip the example if the RBS gem is unavailable.
  #
  # Call this at the top of any example that depends on RBS bridge parsing.
  def skip_unless_rbs_available!
    require 'rbs'
  rescue LoadError
    skip 'RBS not available'
  end

  # Skip the example if the RBS gem or RubyVM::AbstractSyntaxTree is unavailable.
  #
  # Call this at the top of any example that depends on Sorbet/RBS bridge parsing.
  def skip_unless_sorbet_bridge_available!
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    skip 'RubyVM::AbstractSyntaxTree not available' unless defined?(RubyVM::AbstractSyntaxTree)
  end
end
