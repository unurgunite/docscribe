# frozen_string_literal: true

require 'json'

module SarifHelper
  def invocation
    runs[0]['invocations'][0]
  end

  def driver
    runs[0]['tool']['driver']
  end

  def results
    runs[0]['results']
  end

  def runs
    parse_output['runs']
  end

  def parse_write_output
    JSON.parse(capture_stdout { formatter.format_write_summary(state: state, options: options) })
  end

  def parse_output
    JSON.parse(capture_stdout { formatter.format_check_summary(state: state, options: options) })
  end
end
