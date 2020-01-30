class Website
  get "/auth/:platform" do |env|
    case env.params.url["platform"]
    when "discord"
      scope = "identify"
      if env.params.query["scope"]? == "guilds"
        scope = "guilds"
        env.session.bool("store_admin_guilds", true)
      end
      redirect = discord_auth.client.get_authorize_uri(scope) do |url|
        url.add("prompt", "none")
      end
      env.redirect(redirect)
    when "twitch"     then env.redirect(twitch_auth.authorize_uri(""))
    when "streamlabs" then env.redirect(streamlabs_auth.authorize_uri("donations.create"))
    else                   halt env, status_code: 400
    end
  end

  get "/auth/callback/:platform" do |env|
    case env.params.url["platform"]
    when "twitch"
      code = env.params.query["code"]?
      halt env, status_code: 500 unless code
      user = twitch_auth.get_user_id_with_authorization_code(code)
      env.session.bigint("twitch", user)
      user_id = TB::Data::Account.read(:twitch, user).id.to_i64
    when "discord"
      if env.session.bool?("store_admin_guilds")
        access_token = discord_auth.get_access_token(env.params.query, "guilds")
        guilds = discord_auth.get_user_admin_guilds(access_token)
      else
        access_token = discord_auth.get_access_token(env.params.query)
      end

      user = discord_auth.get_user_id(access_token)
      env.session.bigint("discord", user)

      user_id = TB::Data::Account.read(:discord, user).id.to_i64
    when "streamlabs"
      env.redirect("/login") unless user_id = env.session.bigint("user_id")
      access_token = streamlabs_auth.get_access_token(env.params.query)

      TB::Data::Account.update_streamlabs_token(user_id, access_token.access_token)
      env.redirect("/streamlabs")
    else
      halt env, status_code: 400
    end

    env.session.bigint("user_id", user_id)
    if guilds
      env.session.object("admin_guilds", GuildsArray.new(guilds))
    end

    origin = env.session.string?("origin")
    env.session.string("origin", "/")

    env.redirect(origin || "/")
  end
end
