defmodule Justone.Game.ServerSupervisor do
  @moduledoc """
  Helper functions for managing game servers.
  """

  alias Justone.Game.Server

  def start_game_server(game_code) do
    DynamicSupervisor.start_child(Justone.GameSupervisor, {Server, game_code})
  end

  def stop_game_server(game_code) do
    case Registry.lookup(Justone.GameRegistry, game_code) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Justone.GameSupervisor, pid)
      [] -> {:error, :not_found}
    end
  end

  def game_server_exists?(game_code) do
    case Registry.lookup(Justone.GameRegistry, game_code) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  def get_or_start_game_server(game_code) do
    if game_server_exists?(game_code) do
      {:ok, :existing}
    else
      start_game_server(game_code)
    end
  end
end
