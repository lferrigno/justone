defmodule Justone.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JustoneWeb.Telemetry,
      Justone.Repo,
      {DNSCluster, query: Application.get_env(:justone, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Justone.PubSub},
      # Game server registry and supervisor
      {Registry, keys: :unique, name: Justone.GameRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Justone.GameSupervisor},
      # Recover active games from database on startup
      Justone.Game.Recovery,
      # Presence for tracking players in games
      JustoneWeb.Presence,
      # Start to serve requests, typically the last entry
      JustoneWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Justone.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JustoneWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
