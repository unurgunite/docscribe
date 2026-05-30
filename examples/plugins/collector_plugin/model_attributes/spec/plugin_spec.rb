# frozen_string_literal: true

require 'parser/current'
require 'docscribe/plugin'
require 'tmpdir'
require_relative '../schema_parser/schema_parser'
require_relative '../plugin'

RSpec.describe 'ModelAttributes integration' do
  let(:root) { Dir.mktmpdir }
  let(:schema_path) { File.join(root, 'db', 'schema.rb') }
  let(:plugin) { DocscribePlugins::ModelAttributes.new(root: root) }

  before do
    # Create db/schema.rb with test tables
    FileUtils.mkdir_p(File.dirname(schema_path))
    File.write(schema_path, <<~RUBY)
      ActiveRecord::Schema.define(version: 2024_01_01_000000) do
        create_table "users", force: :cascade do |t|
          t.string "email", null: false
          t.string "name"
          t.string "surname"
          t.boolean "is_admin", default: false
          t.integer "age"
          t.boolean "deleted", default: false
          t.datetime "created_at", null: false
          t.datetime "updated_at", null: false
        end

        create_table "posts", force: :cascade do |t|
          t.string "title"
          t.text "body"
          t.integer "view_count", default: 0
          t.boolean "published"
          t.boolean "draft"
          t.datetime "published_at"
          t.references "user", null: false, foreign_key: true
        end
      end
    RUBY

    Docscribe::Plugin::Registry.register(plugin)
  end

  after do
    Docscribe::Plugin::Registry.clear!
    FileUtils.rm_rf(root)
  end

  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'User model' do
    it 'generates Boolean @return for is_admin' do
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

    it 'generates String @return for email' do
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

    it 'generates Integer @return for age' do
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

    it 'generates Boolean @return for comparison' do
      code = <<~RUBY
        class User < ApplicationRecord
          def adult?
            age >= 18
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Boolean]')
    end

    it 'handles string concatenation' do
      code = <<~RUBY
        class User < ApplicationRecord
          def fullname
            name + surname
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [String]')
    end
  end

  describe 'Post model' do
    it 'generates String @return for title' do
      code = <<~RUBY
        class Post < ApplicationRecord
          def title_upcased
            title.upcase
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [String]')
    end

    it 'generates Integer @return for view_count' do
      code = <<~RUBY
        class Post < ApplicationRecord
          def doubled_views
            view_count * 2
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @return [Integer]')
    end

    it 'generates Boolean @return for published?' do
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
  end

  describe 'namespaced models' do
    before do
      plugin.instance_variable_set(:@schema_tables, { 'admin_users' => { 'is_admin' => 'boolean', 'email' => 'string' } })
    end

    it 'handles Admin::User mapping' do
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
  end

  describe 'non-model classes' do
    xit 'does not generate plugin docs' do
      code = <<~RUBY
        class EmailValidator
          def valid?(email)
            true
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).not_to include('return')
      # The plugin should not generate docs for non-ActiveRecord classes
      # (collector still generates default docs)
    end
  end

  describe 'idempotency' do
    it 'does not duplicate docs on second run' do
      code = <<~RUBY
        class User < ApplicationRecord
          def admin?
            is_admin
          end
        end
      RUBY

      first  = rewrite(code)
      second = rewrite(first)

      first_count  = first.scan('# @return [Boolean]').size
      second_count = second.scan('# @return [Boolean]').size

      expect(second_count).to eq(first_count)
    end
  end
end
