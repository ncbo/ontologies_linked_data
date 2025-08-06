module LinkedData
  module Models
    module Notes
      class Reply < LinkedData::Models::Base
        model :reply, name_with: lambda { |inst| uuid_uri_generator(inst) }

        attribute :body, enforce: [:existence]
        attribute :creator, enforce: [:existence, :user]
        attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
        attribute :parent, enforce: [LinkedData::Models::Notes::Reply]
        attribute :children, inverse: {on: :reply, attribute: :parent}

        serialize_default :body, :creator, :created, :children
        serialize_filter lambda {|inst| serialize_filter(inst)}
        embed :children

        system_controlled :creator, :created

        def self.serialize_filter(inst)
          attributes = inst.class.hypermedia_settings[:serialize_default].dup
          children_loaded = inst.loaded_attributes.include?(:children)
          children_have_attributes = children_loaded && !(inst.children.first || Reply.new).loaded_attributes.empty?
          attributes.delete(:children) unless children_loaded && children_have_attributes
          attributes
        end

      end
    end
  end
end
