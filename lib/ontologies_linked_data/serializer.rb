require 'ontologies_linked_data/media_types'
require 'ontologies_linked_data/serializers/serializers'

module LinkedData
  class Serializer
    class AcceptHeaderError < StandardError; end

    def self.build_response(env, options = {})
      status = options[:status] || 200
      headers = options[:headers] || {}
      body = options[:body] || ""
      obj = options[:ld_object] || body

      req = Rack::Request.new(env)
      params = req.params

      begin
        best = best_response_type(env, params)

        # Error out if we don't support the foramt
        unless LinkedData::MediaTypes.supported_base_type?(best)
          return response(:status => 415)
        end

        response(
          :status => status,
          :content_type => "#{LinkedData::MediaTypes.media_type_from_base(best)};charset=utf-8",
          :body => serialize(best, obj, params, Rack::Request.new(env)),
          :headers => headers
        )
      rescue AcceptHeaderError => ae
        handle_error(ae, 400, ae.message)
      rescue Exception => e
        handle_error(e)
      end
    end

    def self.best_response_type(env, params)
      # Client accept header
      accept = env['rack-accept.request']
      # Out of the media types we offer, which would be best?
      begin
        best = LinkedData::MediaTypes.base_type(accept.best_media_type(LinkedData::MediaTypes.all)) unless accept.nil?
      rescue
        accept_header_error = "Accept header `#{env['HTTP_ACCEPT']}` is invalid"
      end
      # Try one other method to get the media type
      best ||= LinkedData::MediaTypes.base_type(env["HTTP_ACCEPT"])
      # If user provided a format via query string, override the accept header
      best = params["format"].to_sym if params["format"]
      # We raise an accept header parse error here if user doesn't provide a format in the parameter
      raise AcceptHeaderError, accept_header_error if !best && accept_header_error
      # Default format if none is provided
      best ||= LinkedData::MediaTypes::DEFAULT
    end

    private

    def self.handle_error(error, status = 500, message = "Internal server error")
      begin
        if print_stacktrace?
          message = error.message + "\n\n  " + error.backtrace.join("\n  ")
          ::LOGGER.debug message
          response(:status => status, :body => message)
        else
          response(:status => status, :body => message)
        end
      rescue Exception => e1
        message = e1.message + "\n\n  " + e1.backtrace.join("\n  ")
        ::LOGGER.debug message
        response(:status => status, :body => message)
      end
    end

    def self.response(options = {})
      status = options[:status] || 200
      headers = options[:headers] || {}
      body = options[:body] || ""
      content_type = options[:content_type] || "text/plain"
      content_length = options[:content_length] || body.bytesize.to_s
      raise ArgumentError("Body must be a string") unless body.kind_of?(String)
      headers.merge!({"Content-Type" => content_type, "Content-Length" => content_length})
      [status, headers, [body]]
    end

    def self.serialize(type, obj, params, request)
      
      lang = self.get_language(params)

      only = params['display'] || []
      only = only.split(',') unless only.is_a?(Array)
      all = only[0] == 'all'
      only = all ? [] : only

      options = { only: only, lang: lang, all: all, params: params, request: request } 
      LinkedData::Serializers.serialize(obj, type, options)
    end

    def self.print_stacktrace?
      if respond_to?("development?")
        development?
      elsif ENV["rack.test"]
        true
      elsif ENV['RACK_ENV'] && ["development", "test"].include?(ENV['RACK_ENV'].downcase)
        true
      else
        false
      end
    end

    def self.get_language(params)
      lang = params['lang'] || params['language'] ||  Goo.main_languages&.first.to_s || 'en'
      lang = lang.split(',').map {|l| l.downcase.to_sym}
      return lang.length == 1 ? lang.first : lang
    end

  end
end