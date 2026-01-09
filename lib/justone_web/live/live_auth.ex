defmodule JustoneWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that extracts session_id and makes it available.
  """
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    session_id = Map.get(session, "session_id")

    {:cont, assign(socket, :session_id, session_id)}
  end
end
