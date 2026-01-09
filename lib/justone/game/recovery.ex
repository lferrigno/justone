defmodule Justone.Game.Recovery do
  @moduledoc """
  Recovers active game servers from persisted state on application startup.
  """
  use GenServer

  alias Justone.Game
  alias Justone.Game.ServerSupervisor

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Delay recovery slightly to ensure all supervisors are ready
    Process.send_after(self(), :recover_games, 1000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:recover_games, state) do
    recover_games()
    {:noreply, state}
  end

  defp recover_games do
    games = Game.list_recoverable_games()

    if length(games) > 0 do
      Logger.info("Recovering #{length(games)} game(s) from persisted state...")

      Enum.each(games, fn game ->
        case ServerSupervisor.start_game_server(game.code) do
          {:ok, _pid} ->
            Logger.info("Recovered game #{game.code}")

          {:error, {:already_started, _pid}} ->
            Logger.debug("Game #{game.code} already running")

          {:error, reason} ->
            Logger.warning("Failed to recover game #{game.code}: #{inspect(reason)}")
        end
      end)

      Logger.info("Game recovery complete")
    else
      Logger.debug("No games to recover")
    end
  end
end
