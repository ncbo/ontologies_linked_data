require 'set'

module LinkedData
  module Security
    class Authorization
      APIKEYS_FOR_AUTHORIZATION = {}
      USER_APIKEY_PARAM = 'userapikey'.freeze
      API_KEY_PARAM = 'apikey'.freeze

      def initialize(app = nil)
        @app = app
      end

      ROUTES_THAT_BYPASS_SECURITY = Set.new([
                                              "/",
                                              "/documentation",
                                              "/jsonview/jsonview.css",
                                              "/jsonview/jsonview.js"
                                            ])

      def call(env)
        req = Rack::Request.new(env)
        params = req.params

        apikey = find_apikey(env, params)
        status = 200
        error_message = ''

        if !apikey
          status = 401
          error_message = <<-MESSAGE
            You must provide an API Key either using the query-string parameter `apikey` or the `Authorization` header: `Authorization: apikey token=my_apikey`. 
            Your API Key can be obtained by logging in at #{LinkedData.settings.ui_host}/account"
          MESSAGE
        elsif !authorized?(apikey, env)
          status = 401
          error_message = "You must provide a valid API Key. Your API Key can be obtained by logging in at #{LinkedData.settings.ui_host}/account"
        end

        response = {
          status: status,
          error: error_message
        }

        if status.eql?(401) && !bypass?(env)
          LinkedData::Serializer.build_response(env, status: status, body: response)
        else
          # unfrozen params so that they can be encoded by Rack using occurring after updating the gem RDF to  v3.0
          env["rack.request.form_hash"]&.transform_values!(&:dup)
          env["rack.request.query_hash"]&.transform_values!(&:dup)
          status, headers, response = @app.call(env)
          save_apikey_in_cookie(env, headers, apikey, params)
          [status, headers, response]
        end
      end

      # Skip auth unless security is enabled or for routes we know should be allowed
      def bypass?(env)
        return !LinkedData.settings.enable_security \
          || ROUTES_THAT_BYPASS_SECURITY.include?(env["REQUEST_PATH"]) \
          || env["HTTP_REFERER"] && env["HTTP_REFERER"].start_with?(LinkedData.settings.rest_url_prefix)
      end

      ##
      # Inject a cookie with the API Key if it is present and we're in HTML content type
      COOKIE_APIKEY_PARAM = "ncbo_apikey"

      def save_apikey_in_cookie(env, headers, apikey, params)
        # If we're using HTML, inject the apikey in a cookie (ignores bad accept headers)
        best = nil
        begin
          best = LinkedData::Serializer.best_response_type(env, params)
        rescue LinkedData::Serializer::AcceptHeaderError
          # Ignored
        end

        return unless best == LinkedData::MediaTypes::HTML

        Rack::Utils.set_cookie_header!(headers, COOKIE_APIKEY_PARAM, {
          value: apikey,
          path: '/',
          expires: Time.now + 90 * 24 * 60 * 60
        })
      end

      def find_apikey(env, params)
        apikey = user_apikey(env, params)
        return apikey if apikey

        apikey = params[API_KEY_PARAM]
        return apikey if apikey

        apikey = request_header_apikey(env)
        return apikey if apikey

        cookie_apikey(env)
      end

      def authorized?(apikey, env)
        return false if apikey.nil?

        if APIKEYS_FOR_AUTHORIZATION.key?(apikey)
          store_user(APIKEYS_FOR_AUTHORIZATION[apikey], env)
        else
          # Exclude inverse attributes (e.g. :provisionalClasses) from the auth load —
          # they fan out across all referencing instances and aren't needed to
          # establish identity.
          # TODO: this could be tightened further to an explicit allowlist
          # (:username, :customOntology, role: [:role] are the only attrs the
          # middleware and access-control checks actually read on every request);
          # leaving forward scalars in for now to avoid surprising any callers
          # that quietly depend on profile fields being preloaded.
          attrs_to_load = LinkedData::Models::User.attributes(:all) - LinkedData::Models::User.attributes(:inverse)
          user = LinkedData::Models::User.where(apikey: apikey)
                                         .include(attrs_to_load)
                                         .first
          return false if user.nil?

          # This will kind-of break if multiple apikeys exist
          # Though it is also kind-of ok since we just want to know if a user with corresponding key exists

          store_user(user, env)
        end
        true
      end

      def store_user(user, env)
        Thread.current[:remote_user] = user
        env.update("REMOTE_USER" => user)
      end

      private

      def request_header_apikey(env)
        header_auth = get_header_auth(env)
        return if header_auth.empty?

        auth_type, token_string = header_auth.split(/\s+/, 2)
        return unless auth_type&.downcase == API_KEY_PARAM
        return if token_string.nil? || token_string.empty?

        token = Rack::Utils.parse_query(token_string)
        return if token['token'].nil? || token['token'].empty?
        # Strip spaces from start and end of string
        apikey = token['token'].gsub(/\"/, "")
        # If the user apikey is passed, use that instead
        if token[USER_APIKEY_PARAM] && !token[USER_APIKEY_PARAM].empty?
          apikey_authed = authorized?(apikey, env)
          return unless apikey_authed

          apikey = token[USER_APIKEY_PARAM].gsub(/\"/, "")
        end
        apikey
      end

      def cookie_apikey(env)
        return unless env["HTTP_COOKIE"]

        cookie = Rack::Utils.parse_cookies(env)
        cookie[COOKIE_APIKEY_PARAM]
      end

      def get_header_auth(env)
        env["HTTP_AUTHORIZATION"] || env["Authorization"] || ''
      end

      def user_apikey(env, params)
        return unless (params["apikey"] && params["userapikey"])

        apikey_authed = authorized?(params[API_KEY_PARAM], env)

        return unless apikey_authed

        params[USER_APIKEY_PARAM]
      end

    end
  end
end
