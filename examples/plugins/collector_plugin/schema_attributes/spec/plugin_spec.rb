# frozen_string_literal: true

require 'docscribe/plugin'
require_relative '../plugin'

RSpec.describe DocscribePlugins::SchemaAttributes do
  let(:plugin) { described_class.new }

  before { Docscribe::Plugin::Registry.register(plugin) }
  after  { Docscribe::Plugin::Registry.clear! }

  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'collect' do
    it 'documents columns for ApplicationRecord models' do
      plugin.instance_variable_set(:@schema,
                                   { 'users' => [{ name: 'email', type: 'string' }, { name: 'is_admin', type: 'boolean' }] })

      code = <<~RUBY
        class User < ApplicationRecord
          def admin?
            is_admin
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] email')
      expect(out).to include('#   @return [String]')
      expect(out).to include('# @!attribute [r] is_admin')
      expect(out).to include('#   @return [Boolean]')
    end

    it 'maps integer columns to Integer' do
      plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'view_count', type: 'integer' }] })

      code = <<~RUBY
        class Post < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] view_count')
      expect(out).to include('#   @return [Integer]')
    end

    it 'maps datetime columns to Time' do
      plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'published_at', type: 'datetime' }] })

      code = <<~RUBY
        class Post < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] published_at')
      expect(out).to include('#   @return [Time]')
    end

    it 'maps json columns to Hash' do
      plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'metadata', type: 'json' }] })

      code = <<~RUBY
        class Post < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] metadata')
      expect(out).to include('#   @return [Hash]')
    end

    it 'skips standard Rails columns' do
      plugin.instance_variable_set(:@schema,
                                   { 'users' => [{ name: 'id', type: 'integer' }, { name: 'created_at', type: 'datetime' }, { name: 'updated_at', type: 'datetime' },
                                                 { name: 'email', type: 'string' }] })

      code = <<~RUBY
        class User < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).not_to include('# @!attribute [r] id')
      expect(out).not_to include('# @!attribute [r] created_at')
      expect(out).not_to include('# @!attribute [r] updated_at')
      expect(out).to include('# @!attribute [r] email')
    end

    it 'does not document non-ActiveRecord classes' do
      plugin.instance_variable_set(:@schema, { 'email_formatters' => [{ name: 'template', type: 'string' }] })

      code = <<~RUBY
        class EmailFormatter
          def format(email)
            email
          end
        end
      RUBY

      out = rewrite(code)
      expect(out).not_to include('# @!attribute [r] template')
    end

    it 'handles namespaced models' do
      plugin.instance_variable_set(:@schema, { 'admin_users' => [{ name: 'role', type: 'string' }] })

      code = <<~RUBY
        class Admin::User < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] role')
      expect(out).to include('#   @return [String]')
    end

    it 'handles ActiveRecord::Base inheritance' do
      plugin.instance_variable_set(:@schema, { 'legacy_users' => [{ name: 'password', type: 'string' }] })

      code = <<~RUBY
        class LegacyUser < ActiveRecord::Base
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] password')
      expect(out).to include('#   @return [String]')
    end

    it 'uses Object for unknown column types' do
      plugin.instance_variable_set(:@schema, { 'users' => [{ name: 'custom_field', type: 'unknown_type' }] })

      code = <<~RUBY
        class User < ApplicationRecord
        end
      RUBY

      out = rewrite(code)
      expect(out).to include('# @!attribute [r] custom_field')
      expect(out).to include('#   @return [Object]')
    end

    it 'is idempotent in safe mode' do
      plugin.instance_variable_set(:@schema, { 'users' => [{ name: 'email', type: 'string' }] })

      code = <<~RUBY
        class User < ApplicationRecord
        end
      RUBY

      first  = rewrite(code)
      second = rewrite(first)

      expect(second.scan('# @!attribute [r] email').length).to eq(1)
    end

    context 'with no schema.rb' do
      it 'returns empty array gracefully' do
        plugin.instance_variable_set(:@schema, {})

        code = <<~RUBY
          class User < ApplicationRecord
          end
        RUBY

        out = rewrite(code)
        expect(out).not_to include('# @!attribute [r]')
      end
    end
  end
end
