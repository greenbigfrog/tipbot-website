class OAuth2::Client
  def get_access_token_using_authorization_code(authorization_code, scope) : AccessToken
    get_access_token do |form|
      form.add("redirect_uri", @redirect_uri)
      form.add("grant_type", "authorization_code")
      form.add("code", authorization_code)
      form.add("scope", scope)
    end
  end
end

module SnowflakeConverter
  def self.from_json(parser : JSON::PullParser) : Int64
    parser.read_string.to_i64
  end

  def self.to_json(value : Int64, builder : JSON::Builder)
    builder.scalar value.to_s
  end
end

struct DiscordUser
  JSON.mapping(
    id: {type: Int64, converter: SnowflakeConverter}
  )
end

struct DiscordGuild
  JSON.mapping(
    id: {type: Int64, converter: SnowflakeConverter},
    name: String,
    icon: String?,
    permissions: Int64
  )
end

class DiscordOAuth2
  def initialize(client_id : String, client_secret : String,
                 redirect_uri : String)
    @client = OAuth2::Client.new("discordapp.com/api/v6",
      client_id,
      client_secret,
      authorize_uri: "/oauth2/authorize",
      redirect_uri: redirect_uri)
  end

  def client
    @client
  end

  def authorize_uri(scope)
    @client.get_authorize_uri(scope)
  end

  def get_access_token(params, scope = "identify")
    @client.get_access_token_using_authorization_code(params["code"], scope)
  end

  def get_user_guilds(access_token)
    client = HTTP::Client.new("discordapp.com", tls: true)
    access_token.authenticate(client)

    raw_json = client.get("/api/v6/users/@me/guilds").body
    Array(DiscordGuild).from_json(raw_json)
  end

  def get_user_admin_guilds(access_token)
    guilds = get_user_guilds(access_token)

    output = Array(DiscordGuild).new

    guilds.each do |guild|
      # Only include guild if user has admin (0x8)
      output << guild if guild.permissions & 0x8 == 0x8
    end

    output
  end

  def get_user_id(access_token)
    client = HTTP::Client.new("discordapp.com", tls: true)
    access_token.authenticate(client)

    raw_json = client.get("/api/v6/users/@me").body
    DiscordUser.from_json(raw_json).id
  end
end
