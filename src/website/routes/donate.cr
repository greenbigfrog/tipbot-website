class Website
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
end
