require 'libxml'

module LinkedData
  module Concerns
    module SubmissionDiffParser

      class DiffReport
        attr_accessor :summary, :changed_classes, :new_classes, :deleted_classes

        def initialize(summary, changed_classes, new_classes, deleted_classes)
          @summary = summary
          @changed_classes = changed_classes
          @new_classes = new_classes
          @deleted_classes = deleted_classes
        end
      end

      class DiffSummary
        attr_accessor :number_changed_classes, :number_new_classes, :number_deleted_classes

        def initialize(number_changed_classes, number_new_classes, number_deleted_classes)
          @number_changed_classes = number_changed_classes
          @number_new_classes = number_new_classes
          @number_deleted_classes = number_deleted_classes
        end
      end

      class ChangedClass
        attr_accessor :class_iri, :class_labels, :new_axioms, :new_annotations, :deleted_annotations, :deleted_axioms

        def initialize(class_iri, class_labels, new_axioms, new_annotations, deleted_axioms, deleted_annotations)
          @class_iri = class_iri
          @class_labels = class_labels
          @new_axioms = new_axioms
          @deleted_axioms = deleted_axioms
          @new_annotations = new_annotations
          @deleted_annotations = deleted_annotations
        end
      end

      class NewClass < ChangedClass; end

      class DeletedClass < ChangedClass; end

      def parse_diff_report(xml_file = self.diffFilePath)
        parser = LibXML::XML::Parser.file(xml_file)
        doc = parser.parse

        # Parse summary
        summary = doc.find_first('//diffSummary')
        diff_summary = DiffSummary.new(
          summary.find_first('numberChangedClasses').content.to_i,
          summary.find_first('numberNewClasses').content.to_i,
          summary.find_first('numberDeletedClasses').content.to_i
        )

        # Parse changed classes
        changed_classes = doc.find('//changedClasses/changedClass').map do |node|
          extract_changes_details ChangedClass, node
        end

        # Parse new classes
        new_classes = doc.find('//newClasses/newClass').map do |node|
          extract_changes_details NewClass, node
        end

        # Parse deleted classes
        deleted_classes = doc.find('//deletedClasses/deletedClass').map do |node|
          extract_changes_details DeletedClass, node
        end

        # Create the DiffReport object
        DiffReport.new(diff_summary, changed_classes, new_classes, deleted_classes)
      end

      def extract_changes_details(klass, node)
        class_iri = node.find_first('classIRI').content.strip
        class_labels = node.find('classLabel').map(&:content)
        new_axioms = node.find('newAxiom').map(&:content)
        new_annotations = node.find('newAnnotation').map(&:content)
        deleted_axioms = node.find('deletedAxiom').map(&:content)
        deleted_annotations = node.find('deletedAnnotation').map(&:content)


        klass.new(class_iri, class_labels, new_axioms, new_annotations, deleted_annotations, deleted_axioms)
      end
    end
  end
end
