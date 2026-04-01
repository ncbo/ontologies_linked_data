require 'bcrypt'
require 'openssl'
require 'base64'
require 'json'
require 'jwt'
require 'faraday'
require 'active_support/core_ext/object/blank'

module LinkedData
  module Models
    module Users
      module OAuthAuthentication

        def self.included base
          base.extend ClassMethods
        end

        module ClassMethods

          def oauth_providers
            LinkedData.settings.oauth_providers
          end

          def oauth_authenticate(token, provider)
            user_data = case provider.to_sym
                        when :github
                          auth_github(token)
                        when :google
                          auth_google(token)
                        when :orcid
                          auth_orcid(token)
                        when :keycloak
                          auth_keycloak(token)
                        else
                          nil
                        end

            create_if_not_exists(user_data) if user_data
          end

          private

          def create_if_not_exists(user_data)
            user = user_by_email(user_data[:email])

            if user.nil?
              auth_create_user(user_data)
            else
              sync_providers_id(user, user_data[:githubId], user_data[:orcidId])
            end
          end

          def sync_providers_id(user, github_id, orcid_id)
            user.bring_remaining
            user.githubId = github_id if user.githubId.blank? && !github_id.blank?
            user.orcidId = orcid_id if user.orcidId.blank? && !orcid_id.blank?
            user.save(override_security: true) if user.valid?
            user
          end

          def auth_create_user(user_data)
            user = User.new(user_data)
            user.password = SecureRandom.hex(16)

            return nil unless user.valid?

            user.save(send_notifications: true)
            user
          end

          def user_by_email(email)
            LinkedData::Models::User.where(email: email).first unless email.nil?
          end

          def user_from_orcid_data(user_data)
            {
              email: user_data['email'],
              firstName: user_data['name']['given-names'],
              lastName: user_data['name']['family-name'],
              username: user_data['email'].split('@').first,
              orcidId: user_data['orcid']
            }
          end

          def auth_orcid(token)
            user_data = token_check(token, :orcid)

            return nil if user_data.nil?

            user_from_orcid_data user_data

          end

          def user_from_google_data(user_data)
            {
              email: user_data['email'],
              firstName: user_data['given_name'],
              lastName: user_data['family_name'],
              username: user_data['email'].split('@').first
            }
          end

          def auth_google(token)
            user_data = token_check(token, :google)

            return nil if user_data.nil?

            user_from_google_data user_data
          end

          def auth_github(token)
            user_data = token_check(token, :github)

            return nil if user_data.nil?

            user_from_github_data user_data
          end

          def user_from_github_data(user_data)
            {
              email: user_data['email'],
              username: user_data['login'],
              firstName: user_data['name'].split(' ').first,
              lastName: user_data['name'].split(' ').drop(1).join(' '),
              githubId: user_data['login']
            }
          end

          def user_from_keycloak_data(user_data)
            {
              email: user_data['email'],
              username: user_data['preferred_username'],
              firstName: user_data['given_name'],
              lastName: user_data['family_name']
            }
          end

          def auth_keycloak(token)
            user_data = token_check(token, :keycloak)

            return nil if user_data.nil?

            user_from_keycloak_data user_data
          end

          def token_check(token, provider)
            provider_config = oauth_providers[provider.to_sym]

            return nil unless provider_config

            if provider_config[:check].eql?(:access_token)
              access_token_check(token, provider_config[:link])
            elsif provider_config[:check].eql?(:jwt_token)
              jwt_token_check(token, provider_config[:cert])
            end
          end

          def jwt_token_check(jwt_token, cert)
            decode_cert = Base64.decode64(cert)
            rsa_public = OpenSSL::X509::Certificate.new(decode_cert).public_key
            begin
              JWT.decode(jwt_token, rsa_public, true, { algorithm: 'HS256' })
            rescue JWT::DecodeError
              nil
            end
          end

          def access_token_check(token, link)
            response = Faraday.new(url: link) do |faraday|
              faraday.headers['Authorization'] = "Bearer #{token}"
              faraday.adapter Faraday.default_adapter
            end.get

            return nil unless response.success?

            JSON.parse(response.body)
          end
        end

      end

    end

  end
end

