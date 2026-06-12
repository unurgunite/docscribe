# frozen_string_literal: true

require 'parser/current'
require 'docscribe/plugin'
require 'tmpdir'

require_relative '../schema_parser/schema_parser'
require_relative '../plugin'

RSpec.describe DocscribePlugins::ModelAttributes do
  let(:plugin) { described_class.new(root: Dir.mktmpdir) }

  before do
    root = plugin.root
    FileUtils.mkdir_p(File.join(root, 'db'))
    File.write(File.join(root, 'db', 'schema.rb'), <<~SCHEMA)
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
    FileUtils.rm_rf(plugin.root)
  end

  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'full parser + plugin pipeline' do
    subject(:out) { rewrite(code) }

    describe 'generates correct Boolean doc from schema.rb' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def admin?
              is_admin
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Boolean]') }

      it 'does not have multiple @return lines' do
        expect(out.scan('# @return [Boolean]').size).to eq(1)
      end
    end

    describe 'generates correct String doc for email' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def formatted_email
              email.upcase
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [String]') }
    end

    describe 'generates correct Integer doc for age' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def age_in_months
              age * 12
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Integer]') }
    end

    describe 'generates correct Boolean for published post' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            def published?
              published
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Boolean]') }
    end

    describe 'handles string concatenation across columns' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def fullname
              name.upcase
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [String]') }
    end

    describe 'handles namespaced models (Admin::User -> admin_users table)' do
      let(:code) do
        <<~RUBY
          class Admin::User < ApplicationRecord
            def admin_role
              is_admin
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Boolean]') }
    end

    describe 'does not generate plugin docs for non-ActiveRecord classes' do
      let(:code) do
        <<~RUBY
          class EmailValidator
            def valid?(email)
              true
            end
          end
        RUBY
      end

      let(:parsed_ast) { Parser::CurrentRuby.parse(code) }
      let(:buffer) do
        b = Parser::Source::Buffer.new('(string)')
        b.source = code
        b
      end

      it { expect(plugin.collect(parsed_ast, buffer)).to be_empty }
    end
  end
end
