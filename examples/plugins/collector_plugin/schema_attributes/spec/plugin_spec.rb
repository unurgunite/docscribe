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
    subject(:out) { rewrite(code) }

    describe 'documents columns for ApplicationRecord models' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            def admin?
              is_admin
            end
          end
        RUBY
      end

      before do
        plugin.instance_variable_set(:@schema,
                                     { 'users' => [{ name: 'email', type: 'string' },
                                                   { name: 'is_admin', type: 'boolean' }] })
      end

      it { is_expected.to include('# @!attribute [r] email') }
      it { is_expected.to include('#   @return [String]') }
      it { is_expected.to include('# @!attribute [r] is_admin') }
      it { is_expected.to include('#   @return [Boolean]') }
    end

    describe 'maps integer columns to Integer' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'view_count', type: 'integer' }] }) }

      it { is_expected.to include('# @!attribute [r] view_count') }
      it { is_expected.to include('#   @return [Integer]') }
    end

    describe 'maps datetime columns to Time' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'published_at', type: 'datetime' }] }) }

      it { is_expected.to include('# @!attribute [r] published_at') }
      it { is_expected.to include('#   @return [Time]') }
    end

    describe 'maps json columns to Hash' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'posts' => [{ name: 'metadata', type: 'json' }] }) }

      it { is_expected.to include('# @!attribute [r] metadata') }
      it { is_expected.to include('#   @return [Hash]') }
    end

    describe 'skips standard Rails columns' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
          end
        RUBY
      end

      before do
        plugin.instance_variable_set(:@schema,
                                     { 'users' => [
                                       { name: 'id', type: 'integer' },
                                       { name: 'created_at', type: 'datetime' },
                                       { name: 'updated_at', type: 'datetime' },
                                       { name: 'email', type: 'string' }
                                     ] })
      end

      it { is_expected.not_to include('# @!attribute [r] id') }
      it { is_expected.not_to include('# @!attribute [r] created_at') }
      it { is_expected.not_to include('# @!attribute [r] updated_at') }
      it { is_expected.to include('# @!attribute [r] email') }
    end

    describe 'does not document non-ActiveRecord classes' do
      let(:code) do
        <<~RUBY
          class EmailFormatter
            def format(email)
              email
            end
          end
        RUBY
      end

      before do
        plugin.instance_variable_set(:@schema, { 'email_formatters' => [{ name: 'template', type: 'string' }] })
      end

      it { is_expected.not_to include('# @!attribute [r] template') }
    end

    describe 'handles namespaced models' do
      let(:code) do
        <<~RUBY
          class Admin::User < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'admin_users' => [{ name: 'role', type: 'string' }] }) }

      it { is_expected.to include('# @!attribute [r] role') }
      it { is_expected.to include('#   @return [String]') }
    end

    describe 'handles ActiveRecord::Base inheritance' do
      let(:code) do
        <<~RUBY
          class LegacyUser < ActiveRecord::Base
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'legacy_users' => [{ name: 'password', type: 'string' }] }) }

      it { is_expected.to include('# @!attribute [r] password') }
      it { is_expected.to include('#   @return [String]') }
    end

    describe 'uses Object for unknown column types' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'users' => [{ name: 'custom_field', type: 'unknown_type' }] }) }

      it { is_expected.to include('# @!attribute [r] custom_field') }
      it { is_expected.to include('#   @return [Object]') }
    end

    describe 'is idempotent in safe mode' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, { 'users' => [{ name: 'email', type: 'string' }] }) }

      it 'does not duplicate on second run' do
        first  = rewrite(code)
        second = rewrite(first)
        expect(second.scan('# @!attribute [r] email').length).to eq(1)
      end
    end

    describe 'with no schema.rb' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
          end
        RUBY
      end

      before { plugin.instance_variable_set(:@schema, {}) }

      it { is_expected.not_to include('# @!attribute [r]') }
    end
  end
end
