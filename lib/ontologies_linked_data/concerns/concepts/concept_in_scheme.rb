module LinkedData
  module Concerns
    module Concept
      module InScheme
        def self.included(base)
          base.serialize_methods :isInActiveScheme
        end

        def isInActiveScheme
          @isInActiveScheme
        end

        def inScheme?(scheme)
          self.inScheme.include?(scheme)
        end

        def load_is_in_scheme(schemes = [])
          included = schemes.select { |s| inScheme?(s) }
          included = [self.submission.get_main_concept_scheme] if included.empty? && schemes&.empty?
          @isInActiveScheme = included
        end

      end
    end
  end
end
