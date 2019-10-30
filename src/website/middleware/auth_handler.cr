class AuthHandler < Kemal::Handler
  # exclude ["/", "/login", "/auth/*"] #  "/auth/callback/:platform"]
  only ["/statistics", "/balance", "/link_accounts", "/deposit", "/api/*", "/configuration/*"]

  def call(env)
    # return call_next(env) if exclude_match?(env)
    return call_next(env) unless only_match?(env)

    env.session.string("origin", env.request.resource)

    user_id = env.session.bigint?("user_id")
    unless user_id
      env.session.bool("show auth notif", true)
      return env.redirect("/login")
    end

    call_next(env)
  end
end
