class Website
  get "/configuration" do |env|
    user = env.session.bigint?("user_id")
    halt env, status_code: 403 unless user.is_a?(Int64)
    default_render("configuration.ecr")
  end

  get "/configuration/guild" do |env|
    user = env.session.bigint?("user_id")
    halt env, status_code: 403 unless user.is_a?(Int64)

    if guild = env.params.query["guild_id"]?
      guild = guild.to_i64

      discord_guilds = env.session.object("admin_guilds").guilds
      discord_guild = discord_guilds.find { |x| x.id == guild }
      halt env, status_code: 403 unless discord_guild

      default_render("configuration_guild.ecr")
    else
      env.redirect("/configuration")
    end
  end
end
