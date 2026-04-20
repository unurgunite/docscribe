# frozen_string_literal: true

require 'docscribe/plugin'
require_relative '../plugin'

RSpec.describe DocscribePlugins::RailsAssociations do
  let(:plugin) { described_class.new }

  before { Docscribe::Plugin::Registry.register(plugin) }
  after  { Docscribe::Plugin::Registry.clear! }

  # Method documentation.
  #
  # @param [Object] code Param documentation.
  # @return [Object]
  def rewrite(code)
    Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
  end

  describe 'belongs_to' do
    it 'documents a simple belongs_to' do
      code = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] user')
      expect(out).to include('#   @return [User]')
    end

    it 'uses ApplicationRecord for polymorphic belongs_to' do
      code = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :requestable, polymorphic: true, optional: true
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] requestable')
      expect(out).to include('#   Associated requestable (polymorphic) object.')
      expect(out).to include('#   @return [ApplicationRecord]')
    end

    it 'respects class_name option' do
      code = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :author, class_name: 'User'
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('#   @return [User]')
    end
  end

  describe 'has_many' do
    it 'documents a simple has_many' do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :songs, dependent: :destroy
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] songs')
      expect(out).to include('#   Returns the associated songs.')
      expect(out).to include('#   @return [Array<Song>]')
    end

    it 'respects class_name option' do
      code = <<~RUBY
        class User < ApplicationRecord
          has_many :posts, class_name: 'Article'
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('#   @return [Array<Article>]')
    end
  end

  describe 'has_one' do
    it 'documents has_one' do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_one :profile
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] profile')
      expect(out).to include('#   @return [Profile]')
    end
  end

  describe 'has_and_belongs_to_many' do
    it 'documents habtm' do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_and_belongs_to_many :tags
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] tags')
      expect(out).to include('#   @return [Array<Tag>]')
    end
  end

  describe 'idempotency' do
    it 'does not duplicate docs on second run in safe mode' do
      code = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
        end
      RUBY

      first  = rewrite(code)
      second = rewrite(first)

      expect(second.scan('# @!attribute [r] user').length).to eq(1)
    end
  end

  describe 'mixed file' do
    it 'documents associations and regular methods independently' do
      code = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
          has_many :songs, dependent: :destroy

          def process
            true
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @!attribute [r] user')
      expect(out).to include('# @!attribute [r] songs')
      expect(out).to include('# @return [Boolean]')
    end
  end
end
