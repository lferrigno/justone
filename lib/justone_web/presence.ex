defmodule JustoneWeb.Presence do
  use Phoenix.Presence,
    otp_app: :justone,
    pubsub_server: Justone.PubSub
end
