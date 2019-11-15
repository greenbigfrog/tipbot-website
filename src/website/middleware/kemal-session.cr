class GuildsArray
  def to_json(io)
    @guilds.to_json(io)
  end

  def self.from_json(io)
    self.new(Array(DiscordGuild).from_json(io))
  end

  include Kemal::Session::StorableObject

  getter guilds : Array(DiscordGuild)

  def initialize(@guilds : Array(DiscordGuild))
  end
end
