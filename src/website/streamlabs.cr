module Streamlabs
  def self.create_donation(access_token : String, identifier : Int64,
                           amount : BigDecimal, currency : String, skip_alert : Bool = false,
                           name : String = "Default", message : String = "")
    client = HTTP::Client.new("streamlabs.com", tls: true)

    client.post("/api/v1.0/donations", form: {"access_token": access_token,
                                              "identifier":   identifier.to_s,
                                              "amount":       amount.to_s,
                                              "currency":     currency,
                                              "skip_alert":   skip_alert.to_s,
                                              "name":         name,
                                              "message":      message})
  end
end
