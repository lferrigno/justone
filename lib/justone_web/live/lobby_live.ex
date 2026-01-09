defmodule JustoneWeb.LobbyLive do
  use JustoneWeb, :live_view

  alias Justone.Game
  alias Justone.Game.ServerSupervisor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Justone.PubSub, "lobby")
    end

    games = Game.list_joinable_games()

    {:ok,
     assign(socket,
       games: games,
       show_create_modal: false,
       max_players: 7,
       error: nil
     )}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: true)}
  end

  @impl true
  def handle_event("hide_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false, error: nil)}
  end

  @impl true
  def handle_event("update_max_players", %{"max_players" => value}, socket) do
    max_players = String.to_integer(value)
    {:noreply, assign(socket, max_players: max_players)}
  end

  @impl true
  def handle_event("create_game", _params, socket) do
    session_id = socket.assigns.session_id
    max_players = socket.assigns.max_players

    case Game.create_game(%{
           "owner_session_id" => session_id,
           "max_players" => max_players
         }) do
      {:ok, game} ->
        # Start the game server
        ServerSupervisor.start_game_server(game.code)

        # Broadcast to lobby
        Phoenix.PubSub.broadcast(Justone.PubSub, "lobby", :games_updated)

        {:noreply, push_navigate(socket, to: ~p"/game/#{game.code}")}

      {:error, changeset} ->
        {:noreply, assign(socket, error: "Error creating game: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("refresh_games", _params, socket) do
    games = Game.list_joinable_games()
    {:noreply, assign(socket, games: games)}
  end

  @impl true
  def handle_info(:games_updated, socket) do
    games = Game.list_joinable_games()
    {:noreply, assign(socket, games: games)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-500 to-purple-600 p-4">
      <div class="max-w-4xl mx-auto">
        <header class="text-center mb-8">
          <h1 class="text-4xl md:text-5xl font-bold text-white mb-2">Just One</h1>
          <p class="text-indigo-100">El juego cooperativo de palabras</p>
        </header>

        <div class="bg-white rounded-2xl shadow-xl p-6 mb-6">
          <div class="flex flex-col sm:flex-row justify-between items-center gap-4 mb-6">
            <h2 class="text-2xl font-semibold text-gray-800">Partidas disponibles</h2>
            <div class="flex gap-2">
              <button
                phx-click="refresh_games"
                class="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg transition-colors"
              >
                Actualizar
              </button>
              <button
                phx-click="show_create_modal"
                class="px-6 py-2 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors"
              >
                Crear partida
              </button>
            </div>
          </div>

          <%= if Enum.empty?(@games) do %>
            <div class="text-center py-12">
              <div class="text-6xl mb-4">🎮</div>
              <p class="text-gray-500 text-lg">No hay partidas disponibles</p>
              <p class="text-gray-400">¡Crea una nueva partida para empezar!</p>
            </div>
          <% else %>
            <div class="space-y-3">
              <%= for game <- @games do %>
                <.link
                  navigate={~p"/game/#{game.code}"}
                  class="block p-4 bg-gray-50 hover:bg-indigo-50 rounded-xl transition-colors border-2 border-transparent hover:border-indigo-200"
                >
                  <div class="flex justify-between items-center">
                    <div>
                      <span class="font-mono text-lg font-bold text-indigo-600">
                        {game.code}
                      </span>
                      <span class="ml-3 text-gray-500">
                        {length(game.players)}/{game.max_players} jugadores
                      </span>
                    </div>
                    <div class="text-indigo-500">
                      Unirse →
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="text-center text-indigo-100 text-sm">
          <p>3-20 jugadores • Adivina la palabra • ¡Cuidado con las pistas repetidas!</p>
        </div>
      </div>
    </div>

    <%= if @show_create_modal do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
        <div class="bg-white rounded-2xl shadow-2xl p-6 w-full max-w-md">
          <h3 class="text-2xl font-bold text-gray-800 mb-6">Crear nueva partida</h3>

          <%= if @error do %>
            <div class="mb-4 p-3 bg-red-100 text-red-700 rounded-lg">
              {@error}
            </div>
          <% end %>

          <div class="mb-6">
            <label class="block text-gray-700 font-medium mb-2">
              Máximo de jugadores: {@max_players}
            </label>
            <input
              type="range"
              name="max_players"
              min="3"
              max="20"
              value={@max_players}
              phx-change="update_max_players"
              class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-indigo-600"
            />
            <div class="flex justify-between text-sm text-gray-500 mt-1">
              <span>3</span>
              <span>20</span>
            </div>
          </div>

          <div class="flex gap-3">
            <button
              phx-click="hide_create_modal"
              class="flex-1 px-4 py-3 bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium rounded-lg transition-colors"
            >
              Cancelar
            </button>
            <button
              phx-click="create_game"
              class="flex-1 px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors"
            >
              Crear
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
