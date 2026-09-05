# frozen_string_literal: true

module DaemonSigHelper
  DEMO_RBS_INTEGER = "class Demo\n  def foo: (Integer x) -> Integer\nend\n"
  DEMO_RBS_STRING = "class Demo\n  def foo: (String x) -> String\nend\n"
  DEMO_RUBY = "class Demo\n  def foo(x)\n    x\n  end\nend\n"

  # Method documentation.
  #
  # @return [Object]
  def with_tmp_dir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  # Helpers extracted from daemon_spec.rb for RBS sig cache invalidation tests.
  #
  # @param [String] dir temporary directory
  # @return [Array<String>]
  def sig_pair_after_change(dir)
    daemon = build_sig_daemon(dir, rbs: DEMO_RBS_INTEGER)
    write_ruby("#{dir}/a.rb")
    r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
    update_sig('sig/demo.rbs', DEMO_RBS_STRING)
    r2 = rbs_rewrite(daemon, "#{dir}/a.rb")
    [r1, r2]
  end

  # @param [String] dir temporary directory
  # @return [Array<String>]
  def sig_pair_new_file(dir)
    daemon = build_sig_daemon(dir)
    write_ruby("#{dir}/a.rb")
    write_ruby("#{dir}/b.rb")
    r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
    update_sig('sig/demo.rbs', DEMO_RBS_STRING)
    r2 = rbs_rewrite(daemon, "#{dir}/b.rb")
    [r1, r2]
  end

  # @param [String] dir temporary directory
  # @raise [StandardError]
  # @return [Array<String>]
  def sig_triple_cached(dir)
    daemon = build_sig_daemon(dir)
    write_ruby("#{dir}/a.rb")
    r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
    update_sig('sig/demo.rbs', DEMO_RBS_STRING)
    r2 = rbs_rewrite(daemon, "#{dir}/a.rb")
    allow(Docscribe::InlineRewriter).to receive(:rewrite_with_report) { raise 'should be cached' }
    r3 = rbs_rewrite(daemon, "#{dir}/a.rb")
    [r1, r2, r3]
  end

  # Method documentation.
  #
  # @param [Object] dir Param documentation.
  # @param [DEMO_RBS_INTEGER] rbs Param documentation.
  # @return [Object]
  def build_sig_daemon(dir, rbs: DEMO_RBS_INTEGER)
    FileUtils.mkdir_p('sig')
    File.write('sig/demo.rbs', rbs) if rbs
    daemon = described_class.new(socket_path: "#{dir}/test.sock", idle_timeout: 60)
    daemon.send(:load_dependencies)
    daemon.send(:apply_cli_overrides, rbs_overrides)
    daemon
  end

  # @param [String] dir temporary directory
  # @return [Array<Object>]
  def cache_hit_for(dir)
    prepare_sig_files('sig/a.rbs', "class A\nend\n")
    write_ruby("#{dir}/x.rb", "class A\n  def foo; end\nend\n")
    daemon = build_plain_daemon(dir)
    daemon.send(:apply_cli_overrides, rbs_overrides)
    daemon.send(:rewrite_file, "#{dir}/x.rb", :safe)
    hit = daemon.instance_variable_get(:@file_cache)[["#{dir}/x.rb", :safe]]
    config = daemon.instance_variable_get(:@effective_config) || daemon.instance_variable_get(:@config)
    [hit, daemon, config]
  end

  # @param [String] dir temporary directory
  # @return [Array<String>]
  def custom_vs_default_hashes(dir)
    prepare_sig_files('custom_sig/b.rbs', "class B\nend\n", 'sig/a.rbs', "class A\nend\n")
    daemon = build_plain_daemon(dir)
    [sig_hash_for_config(daemon, ['custom_sig']), sig_hash_for_config(daemon, ['sig'])]
  end

  # @param [String] dir temporary directory
  # @return [Array<String>]
  def sig_hash_pair(dir)
    prepare_sig_files('sig/a.rbs', "class A\nend\n")
    daemon = build_plain_daemon(dir)
    config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => ['sig'] })
    h1 = daemon.send(:sig_hash_for, config)
    write_sig('sig/b.rbs', "class B\nend\n")
    h2 = daemon.send(:sig_hash_for, config)
    [h1, h2]
  end

  # Method documentation.
  #
  # @param [Array] paths_and_contents Param documentation.
  # @return [Object]
  def prepare_sig_files(*paths_and_contents)
    paths_and_contents.each_slice(2) do |path, content|
      write_sig(path, content)
    end
  end

  # Method documentation.
  #
  # @param [Object] path Param documentation.
  # @param [DEMO_RUBY] content Param documentation.
  # @return [Object]
  def write_ruby(path, content = DEMO_RUBY)
    File.write(path, content)
  end

  # Method documentation.
  #
  # @param [Object] daemon Param documentation.
  # @param [Object] file Param documentation.
  # @param [Symbol] strategy Param documentation.
  # @return [Object]
  def rbs_rewrite(daemon, file, strategy: :safe)
    _src, result = daemon.send(:rewrite_file, file, strategy)
    result[:output]
  end

  # Method documentation.
  #
  # @param [Object] path Param documentation.
  # @param [Object] content Param documentation.
  # @param [Float] delay Param documentation.
  # @return [Object]
  def update_sig(path, content, delay: 0.05)
    sleep delay
    write_sig(path, content)
  end

  # Method documentation.
  #
  # @param [Object] dir Param documentation.
  # @param [String] socket Param documentation.
  # @return [Object]
  def build_plain_daemon(dir, socket: 's.sock')
    daemon = described_class.new(socket_path: "#{dir}/#{socket}", idle_timeout: 60)
    daemon.send(:load_dependencies)
    daemon
  end

  # Method documentation.
  #
  # @return [Hash]
  def rbs_overrides
    {
      'rbs' => true,
      'sig_dirs' => [],
      'rbi_dirs' => [],
      'include' => [],
      'exclude' => [],
      'include_file' => [],
      'exclude_file' => [],
      'no_boilerplate' => false
    }
  end

  # Method documentation.
  #
  # @param [Object] daemon Param documentation.
  # @param [Object] sig_dirs Param documentation.
  # @return [Object]
  def sig_hash_for_config(daemon, sig_dirs)
    config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => sig_dirs })
    daemon.send(:sig_hash_for, config)
  end

  # Method documentation.
  #
  # @param [Object] path Param documentation.
  # @param [Object] content Param documentation.
  # @return [Object]
  def write_sig(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
