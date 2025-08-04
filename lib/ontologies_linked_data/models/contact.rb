module LinkedData
  module Models
    class Contact < LinkedData::Models::Base
      model :contact, name_with: lambda { |c| uuid_uri_generator(c) }
      attribute :name, enforce: [:existence, :safe_text_128]
      attribute :email, enforce: [:existence, :email]

      embedded true
    end
  end
end
