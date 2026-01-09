defmodule Justone.Repo do
  use Ecto.Repo,
    otp_app: :justone,
    adapter: Ecto.Adapters.Postgres
end
