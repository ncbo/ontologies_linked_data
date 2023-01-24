module LinkedData
  module Diff
    class << self
      attr_accessor :logger
    end

    class DiffTool
      def initialize(old_file_path, new_file_path)
        @old_file_path = old_file_path
        @new_file_path = new_file_path
      end

      # @return String  generated path file
      def diff
        raise NotImplementedError
      end
    end
    class DiffException < Exception
    end
    class MkdirException < DiffException
    end
    class BubastisDiffException < DiffException
    end
  end
end
require_relative "bubastis_diff"
