module LinkedData
  module Concerns
    module Analytics
      def self.included base
        base.extend ClassMethods
      end

      module ClassMethods
        def load_data(field_name)
          @@redis ||= Redis.new(:host => LinkedData.settings.ontology_analytics_redis_host,
                                :port => LinkedData.settings.ontology_analytics_redis_port,
                                :timeout => 30)
          raw_data = @@redis.get(field_name)
          raw_data.nil? ? Hash.new : Marshal.load(raw_data)
        end

        def analytics_redis_key
          raise NotImplementedError # the class that includes it need to implement it
        end

        def load_analytics_data
          self.load_data(analytics_redis_key)
        end

        def analytics(year = nil, month = nil)
          retrieve_analytics(year, month)
        end

        # A static method for retrieving Analytics for a combination of ontologies, year, month
        def retrieve_analytics(year = nil, month = nil)
          analytics = self.load_analytics_data

          year = year.to_s if year
          month = month.to_s if month

          unless analytics.empty?
            analytics.values.each do |ont_analytics|
              ont_analytics.delete_if { |key, _| key != year } unless year.nil?
              ont_analytics.each { |_, val| val.delete_if { |key, __| key != month } } unless month.nil?
            end
            # sort results by the highest traffic values
            analytics = Hash[analytics.sort_by { |_, v| v[year][month] }.reverse] if year && month
          end
          analytics
        end
      end

    end
  end
end


