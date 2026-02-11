require_relative '../../test_case'

class TestUserOAuthAuthentication < LinkedData::TestCase

  def self.before_suite
    @@fake_responses = {
      github: {
        id: 123456789,
        login: 'github_user',
        email: 'github_user@example.com',
        name: 'GitHub User',
        avatar_url: 'https://avatars.githubusercontent.com/u/123456789'
      },
      google: {
        sub: 'google_user_id',
        email: 'google_user@example.com',
        name: 'Google User',
        given_name: 'Google',
        family_name: 'User',
        picture: 'https://lh3.googleusercontent.com/a-/user-profile-image-url'
      },
      orcid: {
        orcid: '0000-0002-1825-0097',
        email: 'orcid_user@example.com',
        name: {
          "family-name": 'ORCID',
          "given-names": 'User'
        }
      }
    }
  end


  def test_authentication_new_users
    users = []

    @@fake_responses.each do |provider, data|
      WebMock.stub_request(:get, LinkedData::Models::User.oauth_providers[provider][:link])
             .to_return(status: 200, body: data.to_json, headers: { 'Content-Type' => 'application/json' })
      user = LinkedData::Models::User.oauth_authenticate('fake token', provider)
      refute_nil user
      assert user.is_a?(LinkedData::Models::User)
      assert_equal user.email, data[:email]
      users << user
    end

    users.each(&:delete)
  end

  def test_authentication_existent_users
    users = []
    @@fake_responses.each do |provider, data|
      user_hash = LinkedData::Models::User.send("user_from_#{provider}_data", data.stringify_keys)

      user = LinkedData::Models::User.new(user_hash)
      user.githubId = nil
      user.orcidId = nil
      user.password = 'password'

      assert user.valid?

      user.save

      WebMock.stub_request(:get, LinkedData::Models::User.oauth_providers[provider][:link])
             .to_return(status: 200, body: data.to_json, headers: { 'Content-Type' => 'application/json' })
      auth_user = LinkedData::Models::User.oauth_authenticate('fake token', provider)

      assert_equal auth_user.id, user.id

      if provider.eql?(:github)
        assert_equal data[:login], auth_user.githubId
      elsif provider.eql?(:orcid)
        assert_equal data[:orcid], auth_user.orcidId
      end
      users << user
    end
    users.each(&:delete)
  end

end
