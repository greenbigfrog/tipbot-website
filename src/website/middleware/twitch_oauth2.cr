require "twitcr"

class TwitchOAuth2
  def initialize(client_id : String, client_secret : String,
                 redirect_uri : String)
    @client = OAuth2::Client.new("id.twitch.tv",
      client_id,
      client_secret,
      authorize_uri: "/oauth2/authorize",
      redirect_uri: redirect_uri)
  end

  def authorize_uri(scope)
    @client.get_authorize_uri(scope)
  end

  def get_access_token(code)
    @client.get_access_token_using_authorization_code(code)
  end

  def get_user_id(access_token)
    client = HTTP::Client.new("api.twitch.tv", tls: true)
    OAuth2::AccessToken::Bearer.new(access_token, nil, nil, nil, nil).authenticate(client)

    raw_json = client.get("/helix/users").body
    list = Twitcr::UserList.from_json(raw_json)
    raise "Invalid access_token" if list.data.empty?

    list.data.first.id.to_i64
  end

  def get_user_id_with_authorization_code(code)
    get_user_id(get_access_token(code).access_token)
  end
end
