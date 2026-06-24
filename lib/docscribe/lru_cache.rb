# frozen_string_literal: true

module Docscribe
  # Bounded LRU cache with O(1) access and eviction.
  # Used by Server::Daemon for file rewrite caching.
  class LRUCache
    # @param [Integer] max_size
    # @return [void]
    def initialize(max_size = 1000)
      @max_size = max_size
      @data = {}
    end

    # @param [Object] key
    # @return [Object]
    def [](key)
      val = @data[key]
      return nil unless val

      @data.delete(key)
      @data[key] = val
      val
    end

    # @param [Object] key
    # @param [Object] val
    # @return [Object]
    def []=(key, val)
      @data.delete(key) if @data.key?(key)
      @data[key] = val
      @data.shift if @data.size > @max_size
    end

    # @return [void]
    def clear
      @data.clear
    end

    # @return [Boolean]
    def empty?
      @data.empty?
    end

    # @return [Integer]
    def size
      @data.size
    end
  end
end
