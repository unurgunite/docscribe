# frozen_string_literal: true

require 'English'
require 'yard'
require 'fileutils'

GEM_NAME = Bundler.load_gemspec(Dir.glob('*.gemspec').first).name
DOCS_REPO_NAME = "#{GEM_NAME}_docs".freeze
DOCS_REPO_PATH = "../#{DOCS_REPO_NAME}".freeze

namespace :docs do # rubocop:disable Metrics/BlockLength
  desc 'Generate new docs and push them to repo'
  task generate: :clean do
    puts 'Generating docs...'
    YARD::CLI::Yardoc.run
    puts 'OK!'
  end

  desc 'Clean existing docs'
  task :clean do
    if File.directory?('doc')
      FileUtils.rm_rf('doc')
      puts 'Cleaned existing docs directory'
    end
  end

  desc 'Pushes docs to github'
  task push: :generate do
    unless File.directory?(DOCS_REPO_PATH)
      puts "Error: Docs repo not found at #{DOCS_REPO_PATH}"
      puts 'Please clone the docs repo first:'
      puts "  git clone git@github.com:unurgunite/#{DOCS_REPO_NAME}.git #{DOCS_REPO_PATH}"
      exit 1
    end

    puts "Copying docs to #{DOCS_REPO_PATH}..."
    FileUtils.mkdir_p('doc') unless File.directory?('doc')
    FileUtils.cp_r('doc/.', DOCS_REPO_PATH)

    puts 'Changing dir...'
    Dir.chdir(DOCS_REPO_PATH) do
      puts 'Checking git status...'
      status_output = `git status --porcelain`

      if status_output.strip.empty?
        puts 'No changes to commit'
      else
        puts 'Committing git changes...'
        puts `git add .`
        commit_result = `git commit -m "Update docs for #{GEM_NAME} #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"`
        puts commit_result

        if $CHILD_STATUS.success?
          puts 'Pushing to GitHub...'
          push_result = `git push origin master 2>&1`
          puts push_result
          if $CHILD_STATUS.success?
            puts 'Docs successfully pushed!'
          else
            puts 'Push failed!'
            exit 1
          end
        else
          puts 'Commit failed!'
          exit 1
        end
      end
    end
  end

  desc 'Generate and push docs in one command'
  task deploy: :push
end
