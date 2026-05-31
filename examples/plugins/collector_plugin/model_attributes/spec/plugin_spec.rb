# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require_relative '../../../collector_plugin/model_attributes/plugin'

RSpec.describe 'ModelAttributes integration' do
  subject(:out) { rewrite(code) }

  let(:conf) do
    Docscribe::Config.new(
      'emit' => {
        'header' => true,
        'param_tags' => param_tags,
        'return_tag' => true,
        'include_default_message' => false
      }
    )
  end
  let(:schema_content) do
    <<~RUBY
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
  end

  let(:param_tags) { false }

  let(:root) { Dir.mktmpdir('docscribe-model-attributes') }
  let(:schema_path) { File.join(root, 'db', 'schema.rb') }

  let(:plugin) { DocscribePlugins::ModelAttributes.new(root: root) }

  before do
    FileUtils.mkdir_p(File.dirname(schema_path))
    File.write(schema_path, schema_content)
    Docscribe::Plugin::Registry.register(plugin)
  end

  after do
    Docscribe::Plugin::Registry.clear!
    FileUtils.rm_rf(root)
  end

  def rewrite(code)
    inline(code, config: conf, strategy: :safe)
  end

  describe 'User model' do
    let(:code) do
      <<~RUBY
        class User < ApplicationRecord
          def admin?
            is_admin
          end
        end
      RUBY
    end

    it 'generates header with correct return type' do
      expect(out).to include('# +User#admin?+ -> Boolean')
    end

    it 'generates @return with overridden type' do
      expect(out).to include('# @return [Boolean]')
    end

    it 'generates a single @return line' do
      expect(out.scan('# @return [Boolean]').size).to eq(1)
    end
  end

  describe 'User model with params' do
    let(:param_tags) { true }

    let(:code) do
      <<~RUBY
        class User < ApplicationRecord
          def self.by_email(email)
            email
          end
        end
      RUBY
    end

    it 'generates header with overridden return type' do
      expect(out).to include('# +User.by_email+ -> String')
    end

    it 'generates @param from the method signature' do
      expect(out).to include('# @param [Object] email')
    end

    it 'generates @return from plugin override' do
      expect(out).to include('# @return [String]')
    end
  end

  describe 'type inference' do
    describe 'string return' do
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

    describe 'integer return' do
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

    describe 'comparison return' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def adult?
              age >= 18
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Boolean]') }
    end

    describe 'string concatenation' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def fullname
              name + surname
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [String]') }
    end
  end

  describe 'Post model' do
    describe 'string column' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            def title_upcased
              title.upcase
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [String]') }
    end

    describe 'integer column' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            def doubled_views
              view_count * 2
            end
          end
        RUBY
      end

      it { is_expected.to include('# @return [Integer]') }
    end

    describe 'boolean column' do
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
  end

  describe 'namespaced models' do
    before do
      plugin.instance_variable_set(
        :@schema_tables,
        { 'admin_users' => { 'is_admin' => 'boolean', 'email' => 'string' } }
      )
    end

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

  describe 'non-model classes' do
    let(:code) do
      <<~RUBY
        class EmailValidator
          def valid?(email)
            true
          end
        end
      RUBY
    end

    it 'falls back to standard collector output when plugin returns nothing' do
      expect(out).to include('# +EmailValidator#valid?+ -> Boolean')
      expect(out).to include('# @return [Boolean]')
    end
  end

  describe 'idempotency' do
    let(:code) do
      <<~RUBY
        class User < ApplicationRecord
          def admin?
            is_admin
          end
        end
      RUBY
    end

    it 'does not duplicate docs on second run' do
      first = rewrite(code)
      second = rewrite(first)

      expect(second.scan('# @return [Boolean]').size).to eq(first.scan('# @return [Boolean]').size)
    end
  end
end
