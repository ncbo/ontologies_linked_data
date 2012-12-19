module LinkedData
  module Parser
    class <<self
      attr_accessor :logger
    end
    class ParserException < Exception
    end
    class MkdirException < ParserException
    end
    class OWLAPIParserException < ParserException
    end
  end
end
require_relative "owlapi"
