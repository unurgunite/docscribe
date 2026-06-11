# frozen_string_literal: true

require 'docscribe/plugin'
require_relative '../plugin'

RSpec.describe DocscribePlugins::RailsAssociations do
  let(:plugin) { described_class.new }

  before { Docscribe::Plugin::Registry.register(plugin) }
  after  { Docscribe::Plugin::Registry.clear! }

  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'belongs_to' do
    subject(:out) { rewrite(code) }

    describe 'documents a simple belongs_to' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            belongs_to :user
          end
        RUBY
      end

      it { is_expected.to include('# @!attribute [r] user') }
      it { is_expected.to include('#   @return [User]') }
    end

    describe 'uses ApplicationRecord for polymorphic belongs_to' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            belongs_to :requestable, polymorphic: true, optional: true
          end
        RUBY
      end

      it { is_expected.to include('# @!attribute [r] requestable') }
      it { is_expected.to include('#   Associated requestable (polymorphic) object.') }
      it { is_expected.to include('#   @return [ApplicationRecord]') }
    end

    describe 'respects class_name option' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            belongs_to :author, class_name: 'User'
          end
        RUBY
      end

      it { is_expected.to include('#   @return [User]') }
    end
  end

  describe 'has_many' do
    subject(:out) { rewrite(code) }

    describe 'documents a simple has_many' do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            has_many :songs, dependent: :destroy
          end
        RUBY
      end

      it { is_expected.to include('# @!attribute [r] songs') }
      it { is_expected.to include('#   Returns the associated songs.') }
      it { is_expected.to include('#   @return [Array<Song>]') }
    end

    describe 'respects class_name option' do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            has_many :posts, class_name: 'Article'
          end
        RUBY
      end

      it { is_expected.to include('#   @return [Array<Article>]') }
    end
  end

  describe 'has_one' do
    subject(:out) { rewrite(code) }

    let(:code) do
      <<~RUBY
        class Post < ApplicationRecord
          has_one :profile
        end
      RUBY
    end

    it { is_expected.to include('# @!attribute [r] profile') }
    it { is_expected.to include('#   @return [Profile]') }
  end

  describe 'has_and_belongs_to_many' do
    subject(:out) { rewrite(code) }

    let(:code) do
      <<~RUBY
        class Post < ApplicationRecord
          has_and_belongs_to_many :tags
        end
      RUBY
    end

    it { is_expected.to include('# @!attribute [r] tags') }
    it { is_expected.to include('#   @return [Array<Tag>]') }
  end

  describe 'idempotency' do
    let(:code) do
      <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
        end
      RUBY
    end

    it 'does not duplicate docs on second run in safe mode' do
      first  = rewrite(code)
      second = rewrite(first)
      expect(second.scan('# @!attribute [r] user').length).to eq(1)
    end
  end

  describe 'mixed file' do
    subject(:out) { rewrite(code) }

    let(:code) do
      <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
          has_many :songs, dependent: :destroy

          def process
            true
          end
        end
      RUBY
    end

    it { is_expected.to include('# @!attribute [r] user') }
    it { is_expected.to include('# @!attribute [r] songs') }
    it { is_expected.to include('# @return [Boolean]') }
  end
end
