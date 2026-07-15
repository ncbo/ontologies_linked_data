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
          # isInActiveScheme is a SKOS-only concept and is only serialized for
          # SKOS submissions. Skip the main-concept-scheme lookup for non-SKOS
          # (OWL/OBO) submissions, where it would run a Scheme query per node
          # that always returns nothing and is then discarded.
          if included.empty? && schemes&.empty? && submission.skos?
            included = [self.submission.get_main_concept_scheme]
          end
          @isInActiveScheme = included
        end

      end
    end
  end
end
