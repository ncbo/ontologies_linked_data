module LinkedData
  module Models
    class SubmissionStatus < LinkedData::Models::Base
      VALUES = [
        "UPLOADED", "ERROR_UPLOADED",
        "RDF", "ERROR_RDF",
        "RDF_LABELS", "ERROR_RDF_LABELS",
        "OBSOLETE", "ERROR_OBSOLETE",
        "INDEXED", "ERROR_INDEXED",
        "INDEXED_ALL_DATA", "ERROR_INDEXED_ALL_DATA",
        "INDEXED_PROPERTIES", "ERROR_INDEXED_PROPERTIES",
        "METRICS",  "ERROR_METRICS",
        "ANNOTATOR", "ERROR_ANNOTATOR",
        "ARCHIVED", "ERROR_ARCHIVED",
        "DIFF", "ERROR_DIFF"
      ]

      USER_READABLE = {
        "RDF"                      => "Parsed successfully",
        "RDF_ERROR"                => "Error parsing",
        "INDEXED"                  => "Indexed terms for search",
        "ERROR_INDEXED"            => "Error indexing terms for search",
        "INDEXED_ALL_DATA"         => "Indexed all the data of the resource",
        "ERROR_INDEXED_ALL_DATA"   => "Error indexeding all the data of the resource",
        "INDEXED_PROPERTIES"       => "Indexed properties for search",
        "ERROR_INDEXED_PROPERTIES" => "Error indexing properties for search",
        "METRICS"                  => "Class metrics calculated",
        "ERROR_METRICS"            => "Error calculating class metrics",
        "ANNOTATOR"                => "Processed for use in Annotator",
        "ERROR_ANNOTATOR"          => "Error processing for use in Annotator",
        "DIFF"                     => "Created submission version diff successfully",
        "ERROR_DIFF"               => "Error creating submission version diff"
      }

      USER_IGNORE = [
        "UPLOADED", "ERROR_UPLOADED",
        "RDF_LABELS", "ERROR_RDF_LABELS",
        "OBSOLETE", "ERROR_OBSOLETE",
      ]

      model :submission_status, name_with: :code
      attribute :code, enforce: [:existence, :unique]
      attribute :submissions,
              :inverse => { :on => :ontology_submission, :attribute => :submissionStatus }
      enum VALUES

      def error?
        code = get_code_from_id()
        code.start_with?("ERROR_")
      end

      def get_error_status
        return self if error?
        code = get_code_from_id()
        SubmissionStatus.find("ERROR_#{code}").include(:code).first
      end

      def get_non_error_status
        return self unless error?
        code = get_code_from_id()
        code.sub!("ERROR_", "")
        SubmissionStatus.find(code).include(:code).first
      end

      def archived?
        self.id.to_s["ARCHIVED"] && !self.id.to_s["ERROR_ARCHIVED"]
      end

      def get_code_from_id
        self.id.to_s.split("/")[-1]
      end

      def self.readable_statuses(statuses)
        statuses_raw = where.models(statuses).include(:code).to_a
        readable_stats = nil

        # TODO: this code was added to deal with intermittent issues with 4store, where the error:
        # Attribute `code` is not loaded for http://data.bioontology.org/submission_statuses/RDF
        # was thrown for no apparent reason!!!
        begin
          readable_stats = statuses_raw.map { |s| s.code }
        rescue
          i = 0
          num_calls = LinkedData.settings.num_retries_4store
          readable_stats = nil

          while readable_stats.nil? && i < num_calls do
            i += 1
            sleep(1)

            begin
              readable_stats = statuses_raw.map { |s| s.bring(:code); s.code }
            rescue Exception
              readable_stats = nil

              if i == num_calls
                raise $!, "#{$!} after retrying #{i} times...", $!.backtrace
              end
            end
          end
        end

        readable_stats = readable_stats - USER_IGNORE
        readable_stats.sort! {|a,b| VALUES.index(a) <=> VALUES.index(b)}
        readable_stats.map {|s| USER_READABLE[s] || s.capitalize}
      end

      def self.status_ready?(status)
        status = status.is_a?(Array) ? status : [status]
        # Using http://ruby-doc.org/core-2.0/Enumerable.html#method-i-all-3F
        all_typed_correctly = status.all? {|s| s.is_a?(LinkedData::Models::SubmissionStatus)}
        raise ArgumentError, "One or more statuses were not SubmissionStatus objects" unless all_typed_correctly

        ready_status_codes = self.get_ready_status
        status_codes = self.get_status_codes(status)
        return (ready_status_codes - status_codes).size == 0
      end

      def self.get_status_codes(status)
        return status.map { |s| s.get_code_from_id() }
      end

      def self.get_ready_status
        return [
            #"UPLOADED",
            "RDF",
            #"RDF_LABELS",
            #"INDEXED",
            #"METRICS",
            #"ANNOTATOR"
        ]
      end

      def ==(that)
        this_code = get_code_from_id
        if that.is_a?(String)
          # Assume it is a status code and work with it.
          that_code = that
        else
          return false unless that.is_a?(LinkedData::Models::SubmissionStatus)
          that_code = that.get_code_from_id
        end
        this_code == that_code
      end

    end
  end
end

