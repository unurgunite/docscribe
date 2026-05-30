# frozen_string_literal: true

require 'parser/current'
require 'docscribe/plugin'
require 'tmpdir'

# Load parser and plugin from the model_attributes directory
require_relative '../schema_parser/schema_parser'
require_relative '../plugin'

RSpec.describe 'ModelAttributes end-to-end' do
  let(:root) { Dir.mktmpdir }
  let(:schema_path) { File.join(root, 'db', 'schema.rb') }
  let(:plugin) { DocscribePlugins::ModelAttributes.new(root: root) }

  before do
    FileUtils.mkdir_p(File.dirname(schema_path))
    File.write(schema_path, <<~SCHEMA)
      ActiveRecord::Schema.define(version: 2024_01_01_000000) do
        create_table "users", force: :cascade do |t|
          t.string "email", null: false
          t.string "name"
          t.boolean "is_admin", default: false
          t.integer "age"
          t.datetime "created_at", null: false
          t.datetime "updated_at", null: false
        end

        create_table "posts", force: :cascade do |t|
          t.string "title"
          t.text "body"
          t.integer "view_count", default: 0
          t.boolean "published"
          t.datetime "published_at"
        end

        create_table "admin_users", force: :cascade do |t|
          t.boolean "is_admin", default: false
          t.string "email"
        end
      end
    SCHEMA

    Docscribe::Plugin::Registry.register(plugin)
  end

  after do
    Docscribe::Plugin::Registry.clear!
    FileUtils.rm_rf(root)
  end

  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'full parser + plugin pipeline' do
    it 'generates correct Boolean doc from schema.rb' do
      code = <<~RUBY
        class User < ApplicationRecord
          def admin?
            is_admin
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Boolean]')
      # Should not have multiple @return lines
      expect(out.scan('# @return [Boolean]').size).to eq(1)
    end

    it 'generates correct String doc for email' do
      code = <<~RUBY
        class User < ApplicationRecord
          def formatted_email
            email.upcase
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [String]')
    end

    it 'generates correct Integer doc for age' do
      code = <<~RUBY
        class User < ApplicationRecord
          def age_in_months
            age * 12
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Integer]')
    end

    it 'generates correct Boolean for published post' do
      code = <<~RUBY
        class Post < ApplicationRecord
          def published?
            published
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Boolean]')
    end

    it 'handles string concatenation across columns' do
      code = <<~RUBY
        class User < ApplicationRecord
          def fullname
            name.upcase
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [String]')
    end

    it 'handles namespaced models (Admin::User -> admin_users table)' do
      code = <<~RUBY
        class Admin::User < ApplicationRecord
          def admin_role
            is_admin
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Boolean]')
    end

    it 'does not generate plugin docs for non-ActiveRecord classes' do
      code = <<~RUBY
        class EmailValidator
          def valid?(email)
            true
          end
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      buffer = Parser::Source::Buffer.new('(string)')
      buffer.source = code

      results = plugin.collect(ast, buffer)
      expect(results).to be_empty
    end
  end
end
