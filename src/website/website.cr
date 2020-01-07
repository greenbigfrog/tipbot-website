require "kemal"
require "kemal-csrf"
require "kemal-session"
require "oauth2"
require "kemal-session-redis"

require "raven/integrations/kemal"

require "tb"
require "tb-worker"

require "crometheus"

add_handler CSRF.new
add_handler AuthHandler.new

# Prometheus
metrics_handler = Crometheus.default_registry.get_handler
Crometheus.default_registry.path = "/metrics"

add_handler metrics_handler
add_handler Crometheus::Middleware::HttpCollector.new

# Raven
Raven.configure do |config|
  config.async = true
  config.current_environment = Kemal.config.env
end

Kemal.config.logger = Raven::Kemal::LogHandler.new(Kemal::LogHandler.new)

add_handler Raven::Kemal::ExceptionHandler.new

Kemal::Session.config do |config|
  config.secret = ENV["SECRET"]
  config.timeout = 1.hour
  config.engine = Kemal::Session::RedisEngine.new(host: "redis", port: 6379)
end

macro default_render(file)
  render("src/website/views/#{{{file}}}", "src/website/layouts/default.ecr")
end

STDOUT.sync = true

class Website
  CACHE_TIMESTAMP = Time.utc.to_unix

  def self.run
    # Check for potential missed deposits during downtime
    queue_history_deposits_check

    redirect_uri = "#{ENV["HOST"]}/auth/callback/"

    discord_auth = DiscordOAuth2.new(ENV["DISCORD_CLIENT_ID"], ENV["DISCORD_CLIENT_SECRET"], redirect_uri + "discord")
    twitch_auth = TwitchOAuth2.new(ENV["TWITCH_CLIENT_ID"], ENV["TWITCH_CLIENT_SECRET"], redirect_uri + "twitch")
    streamlabs_auth = StreamlabsOAuth2.new(ENV["SL_CLIENT_ID"], ENV["SL_CLIENT_SECRET"], redirect_uri + "streamlabs")

    get "/" do |env|
      default_render("index.ecr")
    end

    get "/terms" do |env|
      default_render("terms.ecr")
    end

    get "/balance" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)
      default_render("balance.ecr")
    end

    get "/deposit" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)
      default_render("deposit.ecr")
    end

    get "/statistics" do |env|
      default_render("statistics.ecr")
    end

    get "/link_accounts" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)
      default_render("link_accounts.ecr")
    end

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

    get "/admin" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)

      # Admins only
      halt env, status_code: 500 unless user == 163607982473609216
      default_render("admin.cr")
    end

    # get "/redirect_auth" do |env|
    #   #       <<-HTML
    #   # <meta charset="UTF-8">
    #   # <meta http-equiv="refresh" content="1; url=http://127.0.0.1:3000/auth">

    #   # <script>
    #   # setTimeout(function(){
    #   #   window.location.href = "http://127.0.0.1:3000/auth"
    #   #   }, 5000);
    #   # </script>

    #   # <title>Page Redirection</title>

    #   # If you are not redirected automatically, follow the <a href='http://127.0.0.1:3000/auth'>link to example</a>
    #   # HTML
    # end

    get "/streamlabs" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)
      streamlabs_token = TB::Data::Account.read_streamlabs_token(user)

      default_render("streamlabs.ecr")
    end

    get "/donate/:id" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)

      receipient = env.params.url["id"].to_i64
      streamlabs_token = TB::Data::Account.read_streamlabs_token(receipient)
      env.redirect "/donate/no_streamlabs_token" unless streamlabs_token

      default_render("donate/donate.ecr")
    end

    get "/donate/no_streamlabs_token" do |env|
      default_render("donate/no_streamlabs_token.ecr")
    end

    get "/login" do |env|
      default_render("login.ecr")
    end

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
        user = twitch_auth.get_user_id_with_authorization_code(env.params.query)
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

    get "/logout" do |env|
      env.session.destroy
      env.redirect("/")
    end

    # walletnotify=curl --retry 10 -X POST http://website:3000/walletnotify?coin=0&tx=%s
    get "/walletnotify" do |env|
      coin = TB::Data::Coin.read(env.params.query["coin"].to_i32)
      tx = env.params.query["tx"]

      TB::Data::Deposit.create(tx, coin, :new)
    end

    # get "/docs" do |env|
    #   # env.redirect("/docs/index.html")
    #   env.redirect("https://github.com/greenbigfrog/discordtipbot/tree/master/docs")
    # end

    # post "/webhook/:coin" do |env|
    #   headers = env.request.headers
    #   json = env.params.json
    #   coin = env.params.url["coin"]

    #   halt env, status_code: 403 unless headers["Authorization"]? == data[coin].dbl_auth

    #   unless json["type"] == "upvote"
    #     puts "Received test webhook call"
    #     halt env, status_code: 204
    #   end
    #   query = json["query"]?
    #   params = HTTP::Params.parse(query.lchop('?')) if query.is_a?(String)
    #   server = params["server"]? if params

    #   user = json["user"]
    #   halt env, status_code: 503 unless user.is_a?(String)
    #   user = user.to_u64

    #   if server
    #     data[coin].extend_premium(Premium::Kind::Guild, server.to_u64, 30.minutes)
    #     msg = "Thanks for voting. Extended premium of #{server} by 15 **x2** minutes"
    #   else
    #     data[coin].extend_premium(Premium::Kind::User, user, 2.hour)
    #     msg = "Thanks for voting. Extended your own personal global premium by 1 **x2** hours"
    #   end

    #   if coin == "dogecoin"
    #     str = "1 DOGE"
    #     amount = 1
    #   else
    #     str = "5 ECA"
    #     amount = 5
    #   end
    #   data[coin].db.exec(SQL, user, amount)

    #   msg = "#{msg}\nAs a christmas present you've received twice as much premium time as well as #{str} courtesy of <@163607982473609216>"

    #   queue.push(Msg.new(coin, user, msg))
    # end

    get "/qr/:link" do |env|
      link = env.params.url["link"]
      env.redirect("https://chart.googleapis.com/chart?cht=qr&chs=300x300&chld=L%7C1&chl=#{link}")
    end

    post "/api/generate_deposit_address" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)

      params = env.params.body
      coin = TB::Data::Coin.read(params["coin"].to_i32)

      address = nil
      begin
        address = TB::Data::DepositAddress.read_or_create(coin, TB::Data::Account.read(user))
      rescue ex
        if ex.message == "Unable to connect to RPC"
          halt env, 503, "Please try again later. Unable to connect to RPC"
        else
          halt env, 500, "Something went wrong. Please visit #{TB::SUPPORT} for support"
        end
      end

      address.to_s
    end

    post "/api/guild_config" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)

      params = env.params.body
      config_id = params["config_id"].to_i64

      guild = TB::Data::Discord::Guild.read_guild_id(config_id)

      guilds = env.session.object("admin_guilds").guilds
      halt env, status_code: 403 unless guilds.any? { |x| x.id == guild }

      prefix = params["prefix"]?
      prefix = nil if prefix == ""

      mention = params["mention"]? ? true : false
      soak = params["soak"]? ? true : false
      rain = params["rain"]? ? true : false

      min_soak = parse_bd(params["min_soak"]?)
      min_soak_total = parse_bd(params["min_soak_total"]?)
      min_rain = parse_bd(params["min_rain"]?)
      min_rain_total = parse_bd(params["min_rain_total"]?)
      min_tip = parse_bd(params["min_tip"]?)
      min_lucky = parse_bd(params["min_lucky"]?)

      TB::Data::Discord::Guild.update_config(config_id, prefix, mention, soak, rain,
        min_soak, min_soak_total, min_rain, min_rain_total,
        min_tip, min_lucky)
      nil
    end

    post "/api/donation/test" do |env|
      user = env.session.bigint?("user_id")
      halt env, status_code: 403 unless user.is_a?(Int64)

      streamlabs_token = TB::Data::Account.read_streamlabs_token(user)
      env.redirect("/streamlabs") unless streamlabs_token

      Streamlabs.create_donation(streamlabs_token.not_nil!, user, BigDecimal.new("1"), "USD")
    end

    post "/api/donation" do |env|
      donor = env.session.bigint?("user_id")
      halt env, status_code: 403 unless donor.is_a?(Int64)

      p = env.params.body

      receipient = p["receipient"].to_i64
      streamlabs_token = TB::Data::Account.read_streamlabs_token(receipient)
      halt env, status_code: 500 unless streamlabs_token

      name = p["name"]
      halt env, status_code: 404 unless name.size >= 2 && name.size <= 25 # && /^\w*$/.match(name) == name
      message = "[ #{p["amount"]} #{p["currency"]} via tipbot.info ]  #{p["message"]}"
      halt env, status_code: 404 unless message.size < 255

      coin = TB::Data::Coin.read.find { |x| x.name_short == p["currency"] }
      halt env, status_code: 404 unless coin

      TB::Data::Account.read(donor).transfer(BigDecimal.new(p["amount"]), coin, receipient, TB::Data::TransactionMemo::DONATION)

      Streamlabs.create_donation(streamlabs_token.not_nil!, donor, BigDecimal.new("1"), "USD", name: name, message: message)
    end

    Kemal.run
  end

  private def self.queue_history_deposits_check
    TB::Worker::HistoryDeposits.new.enqueue
  end

  private def self.parse_bd(string : String?) : BigDecimal?
    return nil if string.nil?
    begin
      BigDecimal.new(string)
    rescue
      nil
    end
  end
end
