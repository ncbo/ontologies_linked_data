require 'rdf/raptor'

module LinkedData
  module Monkeypatches
    module RdfRaptorFfi
      module_function

      # rdf-raptor 3.1/3.2 binds raptor_free_world with zero args, but calls
      # it with a pointer from the AutoPointer finalizer. Linux + ffi 1.17.x
      # raises ArgumentError on shutdown unless the signature is corrected.
      def apply!
        return unless defined?(RDF::Raptor::FFI::V2)

        v2 = RDF::Raptor::FFI::V2
        v2.singleton_class.send(:remove_method, :raptor_free_world) if v2.respond_to?(:raptor_free_world)
        v2.attach_function :raptor_free_world, [:pointer], :void
      end
    end
  end
end

LinkedData::Monkeypatches::RdfRaptorFfi.apply!
