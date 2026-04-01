require 'net/http'
require 'rexml/document'
require 'uri'

module LinkedData::Purl
  class Client
    PURL_ONTOLOGY_PATH = lambda { |acronym| "/ontology/#{acronym}" }
    TARGET_ONTOLOGY_PATH = lambda { |acronym| "/ontologies/#{acronym}/classes" }
    PURL_PATH = lambda { |acronym| "/purl#{PURL_ONTOLOGY_PATH.call(acronym)}" }
    PURL_ADMIN_PATH = lambda { |acronym| "/admin#{PURL_PATH.call(acronym)}" }

    def purl_server_login()
      url = URI("http://#{LinkedData.settings.purl_host}:#{LinkedData.settings.purl_port}/admin/login/login-submit.bsh")
      res = Net::HTTP.post_form(url,
                                'id' => LinkedData.settings.purl_username,
                                'passwd' => LinkedData.settings.purl_password)
      cookie = res.response['set-cookie'].split('; ')[0]
      headers = {
          'Cookie' => cookie,
          'Content-Type' => 'application/x-www-form-urlencoded'
      }

      return headers
    end

    def create_purl(acronym)
      headers = purl_server_login()
      target_url = "#{LinkedData.settings.purl_target_url_prefix}#{TARGET_ONTOLOGY_PATH.call(acronym)}"
      type = "partial"
      maintainers = LinkedData.settings.purl_maintainers
      data = "target=#{target_url}&type=#{type}&maintainers=#{maintainers}"
      http = get_http()
      res, data = http.post(PURL_ADMIN_PATH.call(acronym), data, headers)

      return res.code == "201" || res.code == "409" #already exists
    end

    def fix_purl(acronym)
      headers = purl_server_login()
      target_url = "#{LinkedData.settings.purl_target_url_prefix}#{TARGET_ONTOLOGY_PATH.call(acronym)}"
      type = "partial"
      maintainers = LinkedData.settings.purl_maintainers
      data = URI.encode_www_form("target" => target_url, "type" => type, "maintainers" => maintainers)
      http = get_http()
      post_url = "#{PURL_ADMIN_PATH.call(acronym)}?#{data}"
      res, data = http.put(post_url, nil, headers)

      return res.code == "200"
    end

    def purl_exists(acronym)
      http = get_http()
      res = http.get(PURL_PATH.call(acronym))
      doc = REXML::Document.new(res.body)

      if (doc.elements[1] && doc.elements[1].attributes)
        return doc.elements[1].attributes["status"] == "1"
      end

      return false
    end

    def delete_purl(acronym)
      headers = purl_server_login()
      http = get_http()
      res, _ = http.delete(PURL_ADMIN_PATH.call(acronym), headers)

      return res.code == "200"
    end

    private

    def get_http()
      http = Net::HTTP.new(LinkedData.settings.purl_host, LinkedData.settings.purl_port)
      http.use_ssl = true if LinkedData.settings.purl_port == 443
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      return http
    end
  end
end
