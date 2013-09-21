require 'digest/md5'
require 'time'

module LinkedData::HTTPCache
  def self.invalidate_all
    key_set = LinkedData::HTTPCache::CachableResource::KEY_SET
    keys = redis.smembers(key_set)
    if keys
      keys.each_slice(500_000) {|chunk| redis.del chunk}
      redis.del key_set
    end
  end

  def self.redis
    @redis ||= Redis.new(host: LinkedData.settings.http_cache_redis_host, 
                         port: LinkedData.settings.http_cache_redis_port)
    @redis
  end

  module CachableResource
    KEY_SET = "httpcache:keys"
    KEY_PREFIX = "httpcache:last_modified"
    SEGMENT_KEY_PREFIX = "httpcache:last_modified:segment"
    COLLECTION_KEY_PREFIX = "httpcache:last_modified:collection"

    ##
    # Compare a last modified string to the last modified time for this object
    def last_modified_valid?(last_modified)
      cache_read.eql?(last_modified)
    end

    ##
    # Invalidate the cache entry for this object
    def cache_invalidate
      LinkedData::HTTPCache.redis.hdel cache_prefix_and_segment, cache_key
      cache_segment_invalidate
      self.class.cache_collection_invalidate
    end

    ##
    # Invalidate all entries in the segment to which this object belongs
    def cache_segment_invalidate
      LinkedData::HTTPCache.redis.del cache_prefix_and_segment unless cache_segment.empty?
    end

    ##
    # The last modified time for this segment
    def segment_last_modified
      (LinkedData::HTTPCache.redis.hmget self.class.segment_key_prefix, cache_segment).first
    end

    ##
    # Update the last modified date in the cache for this object
    def cache_write
      time = Time.now.httpdate
      LinkedData::HTTPCache.redis.hmset cache_prefix_and_segment, cache_key, time
      LinkedData::HTTPCache.redis.hmset self.class.segment_key_prefix, cache_segment, time
      LinkedData::HTTPCache.redis.sadd self.class.key_set, cache_prefix_and_segment
      LinkedData::HTTPCache.redis.sadd self.class.key_set, self.class.segment_key_prefix
      self.class.cache_collection_write
      time
    end

    ##
    # The last modified time for this object
    def cache_read
      (LinkedData::HTTPCache.redis.hmget(cache_prefix_and_segment, cache_key) || []).first
    end
    alias :last_modified :cache_read

    ##
    # The cache key for this object
    def cache_key
      if self.class.cache_settings[:cache_key].first
        self.class.cache_settings[:cache_key].first.call(self)
      else
        Digest::MD5.hexdigest(self.id)
      end
    end

    ##
    # The cache key and the segment for the current object
    def cache_prefix_and_segment
      self.class.key_prefix + cache_segment
    end

    ##
    # The object's current segment
    def cache_segment
      segment = self.class.cache_settings[:cache_segment_keys] || []
      instance_prefix = self.class.cache_settings[:cache_segment_instance].first
      segment_prefix = instance_prefix.call(self) if instance_prefix.is_a?(Proc)
      segment = (segment_prefix || []) + segment
      return "" if segment.nil? || segment.empty?
      ":#{segment.join(':')}"
    end

    module ClassMethods
      ##
      # Wrappers for constants so they are available in instance
      def key_set() KEY_SET end
      def key_prefix() KEY_PREFIX end
      def segment_key_prefix() SEGMENT_KEY_PREFIX end

      ##
      # Update the collection last modified date
      def cache_collection_write
        time = Time.now.httpdate
        LinkedData::HTTPCache.redis.hmset cache_collection_prefix, cache_collection_key, time
        LinkedData::HTTPCache.redis.sadd KEY_SET, cache_collection_prefix
        time
      end

      ##
      # Get the collection last modified date
      def cache_collection_read
        (LinkedData::HTTPCache.redis.hmget(cache_collection_prefix, cache_collection_key) || []).first
      end
      alias :collection_last_modified :cache_collection_read

      ##
      # Compare a last modified string to the last modified time for this collection
      def collection_last_modified_valid?(last_modified)
        cache_collection_read.eql?(last_modified)
      end

      ##
      # Invalidate the cache entry for this collection
      def cache_collection_invalidate
        LinkedData::HTTPCache.redis.hdel cache_collection_prefix, cache_collection_key
      end

      ##
      # The cache key for this collection
      def cache_collection_key
        name
      end

      ##
      # The prefix for this collection
      def cache_collection_prefix
        COLLECTION_KEY_PREFIX
      end

      ##
      # Generate a segment for a class type with a given prefix
      def cache_segment(segment_prefix)
        segment = cache_settings[:cache_segment_keys] || []
        segment = segment_prefix + segment
        return "" if segment.nil? || segment.empty?
        ":#{segment.join(':')}"
      end

      ##
      # Add a new last modified for this segment
      def cache_segment_write(segment)
        LinkedData::HTTPCache.redis.hmset SEGMENT_KEY_PREFIX, segment, Time.now.httpdate
        LinkedData::HTTPCache.redis.sadd KEY_SET, SEGMENT_KEY_PREFIX
        cache_collection_write
      end

      ##
      # The last modified time for this segment
      def cache_segment_read(segment)
        (LinkedData::HTTPCache.redis.hmget SEGMENT_KEY_PREFIX, segment).first
      end
      alias :segment_last_modified :cache_segment_read

      ##
      # Timeout (default or set via cache_timeout)
      def max_age
        cache_settings[:cache_timeout].first || 60
      end
    end

    # Internal

    def self.included(base)
      base.extend(ClassMethods)
    end

    def self.store_settings(cls, type, setting)
      cls.cache_settings ||= {}
      cls.cache_settings[type] = setting
    end

    module ClassMethods
      attr_accessor :cache_settings

      # Methods with these names will be created
      # for each entry, allowing values to be
      # stored on a per-class basis
      SETTINGS = [
        :cache_key,
        :cache_timeout,
        :cache_segment_keys,
        :cache_segment_instance,
        :cache_load
      ]

      ##
      # Write methods on the class based on settings names
      SETTINGS.each do |method_name|
        define_method method_name do |*args|
          CachableResource.store_settings(self, method_name, args)
        end
      end

      ##
      # Gets called by each class that inherits from this module
      # or classes that include this module
      def inherited(cls)
        super(cls)
        SETTINGS.each do |type|
          CachableResource.store_settings(cls, type, [])
        end
      end
    end
  end
end
