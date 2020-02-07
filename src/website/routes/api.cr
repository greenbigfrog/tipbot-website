class Website
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
end
