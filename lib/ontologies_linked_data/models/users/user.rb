require 'bcrypt'
require 'securerandom'
require 'ontologies_linked_data/models/users/authentication'
require 'ontologies_linked_data/models/users/role'
require 'ontologies_linked_data/models/users/subscription'

module LinkedData
  module Models
    class User < LinkedData::Models::Base
      include BCrypt
      include LinkedData::Models::Users::Authentication

      attr_accessor :show_apikey

      model :user, name_with: :username
      attribute :username, enforce: [:unique, :existence]
      attribute :email, enforce: [:existence]
      attribute :role, enforce: [:role, :list], :default => lambda {|x| [LinkedData::Models::Users::Role.default]}
      attribute :firstName
      attribute :lastName
      attribute :githubId, enforce: [:unique]
      attribute :orcidId, enforce: [:unique]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :passwordHash, enforce: [:existence]
      attribute :apikey, enforce: [:unique], :default => lambda {|x| SecureRandom.uuid}
      attribute :subscription, enforce: [:list, :subscription]
      attribute :customOntology, enforce: [:list, :ontology]
      attribute :resetToken
      attribute :resetTokenExpireTime
      attribute :provisionalClasses, inverse: { on: :provisional_class, attribute: :creator }

      # Hypermedia settings
      embed :subscription
      embed_values :role => [:role]
      serialize_default :username, :email, :role, :apikey
      serialize_never :passwordHash, :show_apikey, :resetToken, :resetTokenExpireTime
      serialize_filter lambda {|inst| show_apikey?(inst)}

      system_controlled :created, :resetToken, :resetTokenExpireTime, :username

      # Cache
      cache_timeout 3600

      # Access control
      write_access :dup

      def self.show_apikey?(inst)
        # This could get called when we have an instance (serialization)
        # or when we are asking which attributes to load (controller)
        if inst.show_apikey
          return attributes
        else
          return attributes - [:apikey]
        end
      end

      def initialize(attributes = {})
        # Don't allow passwordHash to be set here
        attributes.delete(:passwordHash)

        # If we found a password, create a hash
        if attributes.key?(:password)
          new_password = attributes.delete(:password)
          super(attributes)
          self.password = new_password
        else
          super(attributes)
        end
        self
      end

      def save(*args)
        # Reset ontology cache if user changes their custom set
        if LinkedData.settings.enable_http_cache && self.modified_attributes.include?(:customOntology)
          Ontology.cache_collection_invalidate
          OntologySubmission.cache_collection_invalidate
        end
        super
      end

      def admin?
        return false unless persistent?
        bring(role: [:role])
        return false if role.empty?
        role.map {|r| r.role}.include?(LinkedData::Models::Users::Role::ADMIN)
      end

      def password=(new_password)
        @password = Password.create(new_password)
        set_passwordHash(@password)
      end

      def custom_ontology_id_set
        Set.new(self.customOntology.map {|o| o.id.to_s})
      end

      def to_s
        if self.bring?(:username)
          LinkedData::Utils::Triples.last_iri_fragment self.id.to_s
        else
          self.username.to_s
        end
      end

      private

      def set_passwordHash(password)
        self.passwordHash = password
      end

    end
  end
end
