module LinkedData
  module Concerns
    module OntologySubmission
      module ValidatorsHelpers
        def attr_value(inst, attr)
          inst.bring(attr) if inst.bring?(attr)
          inst.send(attr)
        end

        def previous_submission
          self.bring :ontology if self.bring?(:ontology)
          return if self.ontology.nil?

          self.ontology.bring(:submissions) if self.ontology.bring?(:submissions)
          submissions = self.ontology.submissions

          return if submissions.nil?

          submissions.each { |s| s.bring(:submissionId) }
          # Sort submissions in descending order of submissionId, extract last two submissions
          sorted_submissions = submissions.sort { |a, b| b.submissionId <=> a.submissionId }.reverse

          self.bring :submissionId if self.bring?(:submissionId)
          current_index = sorted_submissions.index { |x| x.submissionId.eql?(self.submissionId) }

          if current_index.nil?
            sorted_submissions.last
          else
            min_index = [current_index - 1, 0].max
            sub = sorted_submissions[min_index]
            sub unless sub.submissionId.eql?(self.submissionId)
          end
        end

        def retired?(inst = self)
          inst.bring :status if inst.bring?(:status)
          inst.status.eql?('retired')
        end

        def deprecated?(inst = self)
          inst.bring :deprecated if inst.bring?(:deprecated)
          inst.deprecated
        end
      end

      module Validators
        include ValidatorsHelpers

        def lexvo_language(inst, attr)
          values = Array(attr_value(inst, attr))

          return if values.all? { |x| x&.to_s&.start_with?('http://lexvo.org/id/iso') }

          [:lexvo_language, "#{attr} values need to be in the lexvo namespace (e.g http://lexvo.org/id/iso639-1/fr)"]
        end

        def deprecated_retired_align(inst, attr)
          [:deprecated_retired_align, "can't be with the status retired and not deprecated"] if !deprecated? && retired?
        end

        def validity_date_retired_align(inst, attr)
          valid_date = attr_value(inst, :valid)

          if deprecated? || retired?
            if valid_date.nil? || (valid_date && valid_date >= DateTime.now)
              [:validity_date_retired_align, "validity date should be before or equal to #{DateTime.now}"]
            end
          elsif valid_date && valid_date <= DateTime.now
            [:validity_date_retired_align,
             "can't be with the status retired  and with validity date should that is before or equal to #{DateTime.now}"]
          end
        end

        def modification_date_previous_align(inst, attr)

          sub = previous_submission
          return if sub.nil?

          sub.bring(:modificationDate) if sub.bring?(:modificationDate) || sub.modificationDate.nil?

          return unless sub.modificationDate

          inst.bring :modificationDate if inst.bring?(:modificationDate)

          return unless inst.modificationDate.nil? || (sub.modificationDate >= inst.modificationDate)
          [:modification_date_previous_align,
           "modification date can't be inferior to the previous submission modification date #{sub.modificationDate}"]

        end

        def include_ontology_views(inst, attr)
          self.bring :ontology if self.bring?(:ontology)
          return if self.ontology.nil?

          self.ontology.bring :views
          views = self.ontology.views

          return if views.nil? || views.empty?

          parts = attr_value(inst, :hasPart) || []
          return if views.all? { |v| parts.include?(LinkedData::Models::Base.replace_url_id_to_prefix(v.id)) }

          [:include_ontology_views, "#{attr} needs to include all the views of the ontology"]

        end
      end

      module UpdateCallbacks
        include ValidatorsHelpers

        def enforce_symmetric_ontologies(inst, attr)
          new_values, deleted_values = new_and_deleted_elements(Array(inst.send(attr)), attr_previous_values(inst, attr))
          deleted_values.each do |val|
            submission, target_ontologies = target_ontologies(attr, val)
            next unless submission

            update_submission_values(inst, attr, submission, target_ontologies, action: :remove)
          end
          new_values.each do |val|
            submission, target_ontologies = target_ontologies(attr, val)
            next unless submission

            update_submission_values(inst, attr, submission, target_ontologies)
          end
        end

        def retired_previous_align(inst, attr)
          return unless retired?

          sub = previous_submission
          return if sub.nil?

          sub.bring_remaining
          sub.status = 'retired'
          sub.valid = DateTime.now if sub.valid.nil?
          sub.deprecated = true
          sub.save
        end

        def deprecate_previous_submissions(inst, attr)
          sub = previous_submission
          return if sub.nil?

          changed = false

          sub.bring_remaining
          unless deprecated?(sub)
            sub.deprecated = true
            changed = true
          end

          unless sub.valid
            inst.bring :modificationDate if inst.bring?(:modificationDate)
            inst.bring :creationDate if inst.bring?(:creationDate)
            sub.valid = inst.modificationDate || inst.creationDate || DateTime.now
            changed = true
          end

          sub.save if changed && sub.valid?
        end

        def include_previous_submission(inst, attr)
          sub = previous_submission
          return if sub.nil?

          values = attr_value(inst, attr)
          is_list = values&.is_a?(Array)
          values = Array(values)

          values += [sub.id] unless values.include?(sub.id)

          inst.send("#{attr}=", is_list ? values : values.first)
        end

        def ontology_inverse_of_callback(inst, attr)
          inverse_of_settings = {
            useImports: :usedBy,
            translationOfWork: :workTranslation,
            generalises: :explanationEvolution
          }

          inverse_attr = inverse_of_settings[attr] ||  inverse_of_settings.key(attr)

          return unless  inverse_attr

          values = Array(attr_value(inst, attr))
          new_values, deleted_values = new_and_deleted_elements(values, attr_previous_values(inst, attr))

          new_values.each do |ontology|
            submission, inverse_values = target_ontologies(inverse_attr, ontology)
            next unless submission

            update_submission_values(inst, inverse_attr, submission, inverse_values, action: :append)
          end

          deleted_values.each do |ontology|
            submission, inverse_values = target_ontologies(inverse_attr, ontology)
            next unless submission

            update_submission_values(inst, inverse_attr, submission, inverse_values, action: :remove)
          end
        end

        private

        def attr_previous_values(inst, attr)
          inst.previous_values ? Array(inst.previous_values[attr]) : []
        end

        def new_and_deleted_elements(current_values, previous_values)
          new_elements = current_values - previous_values
          deleted_elements = previous_values - current_values
          [new_elements, deleted_elements]
        end

        def update_submission_values(inst, attr, submission, target_ontologies, action: :append)
          if action.eql?(:append) && target_ontologies && !target_ontologies.include?(inst.ontology.id)
            target_ontologies << inst.ontology.id
          elsif action.eql?(:remove) && target_ontologies && target_ontologies.include?(inst.ontology.id) # delete
            target_ontologies.delete(inst.ontology.id)
          else
            return
          end
          submission.bring_remaining
          submission.send("#{attr}=", target_ontologies)
          submission.save(callbacks: false)
        end

        def target_ontologies(attr, val)
          ont = LinkedData::Models::Ontology.find(val).first

          return unless ont

          submission = ont.latest_submission || ont.bring(:submissions) && ont.submissions.last
          return unless submission

          submission.bring(attr) if submission.bring?(attr)

          [submission, Array(submission.send(attr)).dup]
        end

      end

      module DefaultCallbacks

        def ontology_has_domain(sub)
          ontology_domain_list = []
          sub.ontology.bring(:hasDomain).hasDomain.each do |domain|
            ontology_domain_list << domain.id
          end
          ontology_domain_list
        end

        def default_sparql_endpoint(sub)
          url = LinkedData.settings.sparql_endpoint_url || ''

          url.strip.blank? ? [] : [RDF::URI.new(url)]
        end
        def open_search_default(sub)
          RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{sub.ontology.acronym}&q=")
        end

        def uri_lookup_default(sub)
          RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{sub.ontology.acronym}&require_exact_match=true&q=")
        end

        def data_dump_default(sub)
          RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{sub.ontology.acronym}/download")
        end

        def csv_dump_default(sub)
          RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{sub.ontology.acronym}/download?download_format=csv")
        end

        def ontology_syntax_default(sub)
          if sub.hasOntologyLanguage.umls?
            RDF::URI.new('http://www.w3.org/ns/formats/Turtle')
          elsif sub.hasOntologyLanguage.obo?
            RDF::URI.new('http://purl.obolibrary.org/obo/oboformat/spec.html')
          end
        end

        def default_hierarchy_property(sub)
          if sub.hasOntologyLanguage.owl?
            Goo.vocabulary(:owl)[:subClassOf]
          elsif sub.hasOntologyLanguage.skos?
            Goo.vocabulary(:skos)[:broader]
          end
        end
      end
    end
  end
end