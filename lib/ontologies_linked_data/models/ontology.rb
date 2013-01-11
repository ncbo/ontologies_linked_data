require_relative "ontology_container"
require_relative "ontology_submission"

module LinkedData
  module Models
    ##
    # This class is a wrapper around the OntologyContainer and OntologySubmission.
    # It allows you to work with a single object that will serialize and read from the two underlying ones.
    class Ontology

      def initialize(attributes = {})
        container = attributes[:container] ||= OntologyContainer.new
        submission = attributes[:submission] ||= OntologySubmission.new(ontology: container, submissionId: container.next_submission_id)
        setup_objs(container, submission)
        unless attributes.empty?
          attributes.each do |attr, value|
            set_val(attr.to_sym, value)
          end
        end
      end

      def self.all
        all = OntologyContainer.all
        all_wrapped = []
        all.each do |container|
          all_wrapped << self.new(container: container, submission: container.latest)
        end
        all_wrapped
      end

      def self.find(param, store_name = nil)
        container = OntologyContainer.find(param, store_name)
        return nil if container.nil?

        self.new(container: container, submission: container.latest)
      end

      def self.where(*args)
        all = OntologyContainer.where(*args)

        all_wrapped = []
        all.each do |container|
          all_wrapped << self.new(container: container, submission: container.latest)
        end
        all_wrapped
      end

      def next_submission_id
        @container.next_submission_id
      end

      def highest_submission_id
        @container.highest_submission_id
      end

      def method_missing(sym, *args, &block)
        if sym.to_s[-1] == "="
          set_val(sym, args)
        elsif goo_method?(sym)
          call_goo_method(sym, args)
        else
          # Find method on object and return it
          @wrapped.each {|obj| return obj.send(sym, *args, &block) if obj.respond_to?(sym) }
          # If we haven't returned then raise a no method exception
          raise NoMethodError
        end
      end

      def delete(in_update=false)
        submissions = @container.submissions rescue []
        submissions.each {|s| s.delete(in_update) unless s.nil?}
        @container.delete(in_update)
        nil
      end

      private

      def setup_objs(container, submission)
        @container = container
        @submission = submission
        @wrapped = [@container, @submission]
      end

      def goo_method?(sym)
        @goo_methods = Set.new(Goo::Base::Resource.instance_methods(false)) if @goo_methods.nil?
        @goo_methods.include?(sym)
      end

      def call_goo_method(sym, args)
        return_vals = []
        @wrapped.each do |obj|
          if args.empty?
            return_vals << obj.send(sym)
          else
            return_vals << obj.send(sym, *args)
          end
        end
        combine_values(return_vals)
      end

      VAL_COMBINER = {
        Array => lambda {|a,b| a + b},
        Hash => lambda {|a,b| a.merge(b)},
        TrueClass => lambda {|a,b| a && b},
        FalseClass => lambda {|a,b| a && b}
      }

      def combine_values(vals)
        return if vals.nil?
        val = VAL_COMBINER[vals[0].class].call(vals[0], vals[1])
        # This will return either the combined value (if exists) or the original
        # DANGER could return unexpected results
        val.nil? ? vals : val
      end

      ##
      # Determine which value goes with which object. Defaults to OntologySubmission.
      def set_val(sym, *args)
        val_was_set = false
        @wrapped.each do |obj|
          if obj.respond_to?(sym)
            val_was_set = true
            set = sym[-1].eql?("=") ? sym : "#{sym}="
            obj.send(set.to_sym, *args)
          end
        end

        # Neither object is defined with this attribute, stick it in submission
        # DANGER could set a value that's supposed to be on the container
        unless val_was_set
          @submission.send(sym, args)
        end
      end

    end
  end
end
