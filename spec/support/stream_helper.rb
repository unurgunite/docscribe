# frozen_string_literal: true

module StreamHelper
  def capture_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = orig
  end

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = orig
  end

  def capture_stdout_stderr
    orig_out = $stdout
    orig_err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    result = yield
    [result, $stdout.string, $stderr.string]
  ensure
    $stdout = orig_out
    $stderr = orig_err
  end
end
