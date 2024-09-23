require 'set'

module LinkedData::Security
  WriteAccessDeniedError = Class.new(StandardError)

  module AccessControl
    DEFAULT_OWNER_ATTRIBUTES = [:creator]

    def read_restricted?
      based_on = (self.class.access_control_settings[:read_restriction_based_on] || []).first
      return read_restricted_based_on?(based_on) if based_on

      restricted_proc = (self.class.access_control_settings[:read_restriction] || []).first
      if restricted_proc.is_a?(Proc)
        restricted = restricted_proc.call(self)
      elsif restricted_proc.is_a?(Symbol)
        restricted = self.send(restricted_proc)
      else
        restricted = restricted_proc || false
      end
      restricted
    end

    def readable?(user)
      return false if user.nil?
      return true if user.admin?
      return true unless read_restricted?
      allowed_user_ids = allowed_user_ids(:read_access)
      allowed_user_ids.include?(user.id)
    end

    def writable?(user)
      return false if user.nil?
      return true if user.admin?
      allowed_user_ids = allowed_user_ids(:write_access)
      allowed_user_ids.include?(user.id)
    end

    def access_based_on?
      not self.class.access_control_settings[:read_restriction_based_on].empty?
    end

    def access_control_load_attrs
      self.class.access_control_load_attrs
    end

    def access_control_load?
      self.class.access_control_load?
    end

    def access_for_all?
      self.class.access_control_settings[:grant_access_to_all].first == true
    end

    private

    def read_restricted_based_on?(based_on)
      if based_on.is_a?(Proc)
        instance_to_base_on = based_on.call(self)
        restricted = instance_to_base_on ? instance_to_base_on.read_restricted?  : false
      elsif based_on.is_a?(LinkedData::Models::Base)
        restricted = based_on.read_restricted?
      elsif based_on.is_a?(Symbol)
        instance_to_base_on = based_on.send(based_on)
        restricted =  instance_to_base_on ? instance_to_base_on.read_restricted?  : false
      else
        restricted = false
      end
      restricted
    end

    def allowed_user_ids(settings)
      target = access_based_on? ? based_on_target : self
      attributes = target.class.access_control_settings[settings].dup
      attributes = attributes + DEFAULT_OWNER_ATTRIBUTES
      user_ids = Set.new
      attributes.each do |attr|
        next unless target.respond_to?(attr)
        users = target.send(attr)
        # There appear to be cases where users = nil, which results in an exception.
        # The next line handles this case.
        next if users.nil?
        users = users.is_a?(Array) ? users : [users]
        users.each {|u| user_ids << u.id}
      end
      user_ids
    end

    def based_on_target
      based_on = (self.class.access_control_settings[:read_restriction_based_on] || []).first

      if based_on.is_a?(Proc)
        target = based_on.call(self)
      elsif based_on.is_a?(LinkedData::Models::Base)
        target = based_on
      elsif based_on.is_a?(Symbol)
        target = based_on.send(based_on)
      end
      target
    end

    def self.filter_unreadable(enumerable, user)
      unless enumerable.is_a?(Hash)
        enumerable.delete_if {|e| e.read_restricted? && !e.readable?(user)}
      end
      enumerable
    end

    # Internal

    def self.included(base)
      base.extend(ClassMethods)
    end

    def self.store_settings(cls, type, setting)
      cls.access_control_settings ||= {}
      cls.access_control_settings[type] = Set.new(setting)
    end

    module ClassMethods
      attr_accessor :access_control_settings

      # Methods with these names will be created
      # for each entry, allowing values to be
      # stored on a per-class basis
      SETTINGS = [
        :read_restriction,
        :read_restriction_based_on,
        :read_access,
        :write_access,
        :access_control_load,
        :grant_access_to_all
      ]

      ##
      # Write methods on the class based on settings names
      SETTINGS.each do |method_name|
        define_method method_name do |*args|
          AccessControl.store_settings(self, method_name, args)
        end
      end

      ##
      # Gets called by each class that inherits from this module
      # or classes that include this module
      def inherited(cls)
        super(cls)
        SETTINGS.each do |type|
          AccessControl.store_settings(cls, type, Set.new)
        end
      end

      def access_control_load_attrs
        cls = self
        attrs = cls.access_control_settings[:access_control_load]
        DEFAULT_OWNER_ATTRIBUTES.each do |attr|
          next unless cls.respond_to?(:attributes) && cls.attributes.include?(attr)
          attrs << attr
        end
        attrs
      end

      def access_control_load?
        cls = self
        attrs = cls.access_control_settings[:access_control_load]
        DEFAULT_OWNER_ATTRIBUTES.each do |attr|
          next unless cls.respond_to?(:attributes) && cls.attributes.include?(attr)
          attrs << attr
        end
        not attrs.empty?
      end

    end
  end
end