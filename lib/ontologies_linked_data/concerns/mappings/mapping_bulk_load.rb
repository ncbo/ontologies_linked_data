module LinkedData
  module Concerns
    module Mappings
      module BulkLoad

        # A method to easily add a new mapping without using ontologies_api
        # Where the mapping hash contain classes, relation, creator and comment)
        def bulk_load_mappings(mappings_hash, user_creator, check_exist: true)
          errors = {}
          loaded = []
          mappings_hash&.each_with_index do |mapping, index|
            loaded << load_mapping(mapping, user_creator, check_exist: check_exist)
          rescue ArgumentError => e
            errors[index] = e.message
          end
          [loaded, errors]
        end

        def load_mapping(mapping_hash, user_creator, check_exist: true)
          LinkedData::Mappings.create_mapping(mapping_hash: mapping_hash, user_creator: user_creator,
                                              check_exist: check_exist)
        end

      end
    end
  end
end





