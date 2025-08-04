module LinkedData
  module Concerns
    module Concept
      module Sort
        module ClassMethods
          def compare_classes(class_a, class_b)
            label_a = ""
            label_b = ""
            class_a.bring(:prefLabel) if class_a.bring?(:prefLabel)
            class_b.bring(:prefLabel) if class_b.bring?(:prefLabel)

            begin
              label_a = class_a.prefLabel unless (class_a.prefLabel.nil? || class_a.prefLabel.empty?)
            rescue Goo::Base::AttributeNotLoaded
              label_a = ""
            end

            begin
              label_b = class_b.prefLabel unless (class_b.prefLabel.nil? || class_b.prefLabel.empty?)
            rescue Goo::Base::AttributeNotLoaded
              label_b = ""
            end

            label_a = class_a.id if label_a.empty?
            label_b = class_b.id if label_b.empty?

            [label_a.downcase] <=> [label_b.downcase]
          end

          def sort_classes(classes)
            classes.sort { |class_a, class_b| compare_classes(class_a, class_b) }
          end

          def sort_tree_children(root_node)
            sort_classes!(root_node.children)
            root_node.children.each { |ch| sort_tree_children(ch) }
          end

          private



          def sort_classes!(classes)
            classes.sort! { |class_a, class_b| LinkedData::Models::Class.compare_classes(class_a, class_b) }
            classes
          end
        end

        def self.included(base)
          base.extend(ClassMethods)
        end
      end
    end
  end
end
