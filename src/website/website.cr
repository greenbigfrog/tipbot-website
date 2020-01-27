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

  class_getter redirect_uri : String = "#{ENV["HOST"]}/auth/callback/"
  class_getter discord_auth : DiscordOAuth2 = DiscordOAuth2.new(ENV["DISCORD_CLIENT_ID"], ENV["DISCORD_CLIENT_SECRET"], redirect_uri + "discord")
  class_getter twitch_auth : TwitchOAuth2 = TwitchOAuth2.new(ENV["TWITCH_CLIENT_ID"], ENV["TWITCH_CLIENT_SECRET"], redirect_uri + "twitch")
  class_getter streamlabs_auth : StreamlabsOAuth2 = StreamlabsOAuth2.new(ENV["SL_CLIENT_ID"], ENV["SL_CLIENT_SECRET"], redirect_uri + "streamlabs")

  def self.run
    # Check for potential missed deposits during downtime
    queue_history_deposits_check

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

    get "/login" do |env|
      origin = env.session.string("origin")
      discord_destination = /\/configuration/.match(origin) ? "/auth/discord?scope=guilds" : "/auth/discord"
      default_render("login.ecr")
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

    get "/qr/:link" do |env|
      link = env.params.url["link"]
      env.redirect("https://chart.googleapis.com/chart?cht=qr&chs=300x300&chld=L%7C1&chl=#{link}")
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
