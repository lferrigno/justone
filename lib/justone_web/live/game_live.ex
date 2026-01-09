defmodule JustoneWeb.GameLive do
  use JustoneWeb, :live_view

  alias Justone.Game
  alias Justone.Game.Server
  alias Justone.Game.ServerSupervisor

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    game = Game.get_game_by_code(code)

    if game do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Justone.PubSub, "game:#{code}")
        ServerSupervisor.get_or_start_game_server(code)
      end

      session_id = socket.assigns.session_id
      player = Game.get_player_by_session(game.id, session_id)

      {:ok,
       assign(socket,
         game_code: code,
         game: game,
         player: player,
         game_state: nil,
         nickname: "",
         clue: "",
         guess: "",
         error: nil,
         joining: false
       )
       |> load_game_state()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Partida no encontrada")
       |> push_navigate(to: ~p"/")}
    end
  end

  defp load_game_state(socket) do
    code = socket.assigns.game_code

    case Server.get_state(code) do
      {:ok, state} -> assign(socket, game_state: state)
      _ -> socket
    end
  end

  @impl true
  def handle_event("update_nickname", %{"nickname" => nickname}, socket) do
    {:noreply, assign(socket, nickname: nickname)}
  end

  @impl true
  def handle_event("join_game", %{"nickname" => nickname}, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    nickname = String.trim(nickname)

    if String.length(nickname) < 1 do
      {:noreply, assign(socket, error: "Ingresa un nombre")}
    else
      socket = assign(socket, joining: true)

      case Server.join(code, session_id, nickname) do
        {:ok, :already_joined} ->
          player = Game.get_player_by_session(socket.assigns.game.id, session_id)
          {:noreply, assign(socket, player: player, error: nil, joining: false)}

        {:ok, player} ->
          {:noreply,
           socket
           |> assign(player: player, error: nil, joining: false)
           |> load_game_state()}

        {:error, :game_full} ->
          {:noreply, assign(socket, error: "La partida está llena", joining: false)}

        {:error, :game_already_started} ->
          {:noreply, assign(socket, error: "La partida ya comenzó", joining: false)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Error al unirse", joining: false)}
      end
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    case Server.start_game(code, session_id) do
      :ok -> {:noreply, socket}
      {:error, :not_owner} -> {:noreply, assign(socket, error: "Solo el creador puede iniciar")}
      {:error, :not_enough_players} -> {:noreply, assign(socket, error: "Mínimo 3 jugadores")}
      {:error, _} -> {:noreply, assign(socket, error: "Error al iniciar")}
    end
  end

  @impl true
  def handle_event("update_clue", %{"clue" => clue}, socket) do
    {:noreply, assign(socket, clue: clue)}
  end

  @impl true
  def handle_event("submit_clue", %{"clue" => clue}, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    clue = String.trim(clue)

    if String.length(clue) < 1 do
      {:noreply, assign(socket, error: "Ingresa una pista")}
    else
      case Server.submit_clue(code, session_id, clue) do
        :ok -> {:noreply, assign(socket, error: nil)}
        {:error, :already_submitted} -> {:noreply, assign(socket, error: "Ya enviaste tu pista")}
        {:error, _} -> {:noreply, assign(socket, error: "Error al enviar pista")}
      end
    end
  end

  @impl true
  def handle_event("reveal_clues", _params, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    case Server.reveal_clues(code, session_id) do
      :ok -> {:noreply, socket}
      {:error, _} -> {:noreply, assign(socket, error: "Error al revelar pistas")}
    end
  end

  @impl true
  def handle_event("update_guess", %{"guess" => guess}, socket) do
    {:noreply, assign(socket, guess: guess)}
  end

  @impl true
  def handle_event("submit_guess", %{"guess" => guess}, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    guess = String.trim(guess)

    if String.length(guess) < 1 do
      {:noreply, assign(socket, error: "Ingresa tu respuesta")}
    else
      case Server.submit_guess(code, session_id, guess) do
        {:ok, _correct} -> {:noreply, assign(socket, error: nil)}
        {:error, _} -> {:noreply, assign(socket, error: "Error al enviar respuesta")}
      end
    end
  end

  @impl true
  def handle_event("next_round", _params, socket) do
    %{game_code: code, session_id: session_id} = socket.assigns

    case Server.next_round(code, session_id) do
      :ok -> {:noreply, socket}
      {:ok, :game_finished} -> {:noreply, socket}
      {:error, _} -> {:noreply, assign(socket, error: "Error al continuar")}
    end
  end

  @impl true
  def handle_event("back_to_lobby", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # PubSub handlers
  @impl true
  def handle_info({:player_joined, _player}, socket) do
    {:noreply, load_game_state(socket)}
  end

  @impl true
  def handle_info({:player_left, _player}, socket) do
    {:noreply, load_game_state(socket)}
  end

  @impl true
  def handle_info({:game_started, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:clue_submitted, _player_id}, socket) do
    {:noreply, load_game_state(socket)}
  end

  @impl true
  def handle_info({:all_clues_submitted, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:clues_revealed, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:guess_submitted, _guess, _correct, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:next_round, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def handle_info({:game_finished, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-500 to-purple-600 p-4">
      <div class="max-w-2xl mx-auto">
        <header class="text-center mb-6">
          <.link navigate={~p"/"} class="text-indigo-100 hover:text-white text-sm mb-2 inline-block">
            ← Volver al lobby
          </.link>
          <h1 class="text-3xl font-bold text-white">
            Partida <span class="font-mono">{@game_code}</span>
          </h1>
        </header>

        <%= if @error do %>
          <div class="bg-red-100 text-red-700 p-3 rounded-lg mb-4 text-center">
            {@error}
          </div>
        <% end %>

        <%= if @player == nil do %>
          <.join_form nickname={@nickname} joining={@joining} />
        <% else %>
          <.game_view
            game_state={@game_state}
            player={@player}
            session_id={@session_id}
            clue={@clue}
            guess={@guess}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp join_form(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6">
      <h2 class="text-2xl font-bold text-gray-800 mb-6 text-center">Unirse a la partida</h2>

      <form phx-submit="join_game" class="space-y-4">
        <div>
          <label class="block text-gray-700 font-medium mb-2">Tu nombre</label>
          <input
            type="text"
            name="nickname"
            value={@nickname}
            placeholder="Ingresa tu nombre"
            maxlength="20"
            class="w-full px-4 py-3 border-2 border-gray-200 rounded-lg focus:border-indigo-500 focus:outline-none text-lg"
            autofocus
            required
          />
        </div>

        <button
          type="submit"
          disabled={@joining}
          class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 disabled:bg-indigo-300 text-white font-medium rounded-lg transition-colors text-lg"
        >
          {if @joining, do: "Uniéndose...", else: "Unirse"}
        </button>
      </form>
    </div>
    """
  end

  defp game_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @game_state do %>
        <.score_bar game_state={@game_state} />

        <%= case @game_state.phase do %>
          <% :waiting -> %>
            <.waiting_room game_state={@game_state} session_id={@session_id} />
          <% :clue_submission -> %>
            <.clue_submission
              game_state={@game_state}
              player={@player}
              clue={@clue}
              session_id={@session_id}
            />
          <% :clue_comparison -> %>
            <.clue_comparison game_state={@game_state} session_id={@session_id} />
          <% :guessing -> %>
            <.guessing_phase
              game_state={@game_state}
              player={@player}
              guess={@guess}
              session_id={@session_id}
            />
          <% :round_result -> %>
            <.round_result game_state={@game_state} session_id={@session_id} />
          <% :finished -> %>
            <.game_finished game_state={@game_state} />
          <% _ -> %>
            <div class="bg-white rounded-2xl p-6 text-center">
              <p class="text-gray-500">Cargando...</p>
            </div>
        <% end %>

        <.players_list game_state={@game_state} />
      <% else %>
        <div class="bg-white rounded-2xl p-6 text-center">
          <p class="text-gray-500">Cargando estado del juego...</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp score_bar(assigns) do
    ~H"""
    <div class="bg-white/20 backdrop-blur rounded-xl p-3 flex justify-between items-center text-white">
      <div>
        <span class="text-sm opacity-75">Ronda</span>
        <span class="ml-2 font-bold">{@game_state.current_round}/{@game_state.total_rounds}</span>
      </div>
      <div>
        <span class="text-sm opacity-75">Puntos</span>
        <span class="ml-2 font-bold text-xl">{@game_state.score}</span>
      </div>
    </div>
    """
  end

  defp waiting_room(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6">
      <h2 class="text-2xl font-bold text-gray-800 mb-4 text-center">Sala de espera</h2>

      <div class="text-center mb-6">
        <p class="text-gray-500 mb-2">Esperando jugadores...</p>
        <p class="text-lg">
          <span class="font-bold text-indigo-600">{length(@game_state.players)}</span>
          <span class="text-gray-500">/ {@game_state.max_players} jugadores</span>
        </p>
      </div>

      <%= if @game_state.owner_session_id == @session_id do %>
        <button
          phx-click="start_game"
          disabled={length(@game_state.players) < 3}
          class="w-full px-4 py-3 bg-green-600 hover:bg-green-700 disabled:bg-gray-300 text-white font-medium rounded-lg transition-colors text-lg"
        >
          <%= if length(@game_state.players) < 3 do %>
            Mínimo 3 jugadores para iniciar
          <% else %>
            Iniciar partida
          <% end %>
        </button>
      <% else %>
        <div class="text-center text-gray-500 py-4">
          Esperando a que el creador inicie la partida...
        </div>
      <% end %>
    </div>
    """
  end

  defp clue_submission(assigns) do
    is_guesser = assigns.player.id == assigns.game_state.guesser_id
    already_submitted = assigns.player.id in assigns.game_state.clues_submitted
    assigns = assign(assigns, is_guesser: is_guesser, already_submitted: already_submitted)

    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6">
      <%= if @is_guesser do %>
        <div class="text-center">
          <div class="text-6xl mb-4">🤔</div>
          <h2 class="text-2xl font-bold text-gray-800 mb-2">¡Eres el adivinador!</h2>
          <p class="text-gray-500">Espera mientras los demás escriben sus pistas...</p>

          <div class="mt-6 bg-gray-100 rounded-xl p-4">
            <p class="text-sm text-gray-500 mb-2">Pistas recibidas</p>
            <p class="text-3xl font-bold text-indigo-600">
              {length(@game_state.clues_submitted)} / {length(@game_state.players) - 1}
            </p>
          </div>
        </div>
      <% else %>
        <div class="text-center mb-6">
          <p class="text-gray-500 mb-2">La palabra secreta es:</p>
          <p class="text-4xl font-bold text-indigo-600 uppercase tracking-wider">
            {@game_state.current_word}
          </p>
        </div>

        <%= if @already_submitted do %>
          <div class="text-center py-4">
            <div class="text-4xl mb-2">✅</div>
            <p class="text-green-600 font-medium">¡Pista enviada!</p>
            <p class="text-gray-500 text-sm mt-2">
              Esperando a los demás ({length(@game_state.clues_submitted)}/{length(
                @game_state.players
              ) - 1})
            </p>
          </div>
        <% else %>
          <form phx-submit="submit_clue" class="space-y-4">
            <div>
              <label class="block text-gray-700 font-medium mb-2">Tu pista (una sola palabra)</label>
              <input
                type="text"
                name="clue"
                placeholder="Escribe tu pista..."
                maxlength="50"
                class="w-full px-4 py-3 border-2 border-gray-200 rounded-lg focus:border-indigo-500 focus:outline-none text-lg"
                autofocus
                required
              />
            </div>

            <button
              type="submit"
              class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors text-lg"
            >
              Enviar pista
            </button>
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp clue_comparison(assigns) do
    is_owner = assigns.game_state.owner_session_id == assigns.session_id

    is_guesser =
      Enum.any?(assigns.game_state.players, fn p ->
        p.session_id == assigns.session_id and p.is_guesser
      end)

    owner_is_guesser =
      Enum.any?(assigns.game_state.players, fn p ->
        p.session_id == assigns.game_state.owner_session_id and p.is_guesser
      end)

    # Owner can reveal, OR if owner is guesser, any non-guesser can reveal
    can_reveal = (is_owner and not is_guesser) or (owner_is_guesser and not is_guesser)
    assigns = assign(assigns, is_guesser: is_guesser, can_reveal: can_reveal)

    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6">
      <%= if @is_guesser do %>
        <div class="text-center">
          <div class="text-6xl mb-4">🙈</div>
          <h2 class="text-2xl font-bold text-gray-800 mb-2">¡No mires!</h2>
          <p class="text-gray-500">Los demás están revisando las pistas duplicadas...</p>
          <p class="text-gray-400 text-sm mt-4">Pronto te mostrarán las pistas válidas</p>
        </div>
      <% else %>
        <h2 class="text-2xl font-bold text-gray-800 mb-4 text-center">Comparando pistas</h2>

        <p class="text-gray-500 text-center mb-6">
          Las pistas repetidas serán eliminadas
        </p>

        <div class="space-y-3 mb-6">
          <%= for clue <- @game_state.revealed_clues do %>
            <div class={[
              "p-4 rounded-xl flex justify-between items-center",
              if(clue.is_duplicate,
                do: "bg-red-50 border-2 border-red-200",
                else: "bg-green-50 border-2 border-green-200"
              )
            ]}>
              <div>
                <span class="font-medium text-gray-700">{clue.player_nickname}:</span>
                <span class={[
                  "ml-2 font-bold",
                  if(clue.is_duplicate, do: "text-red-500 line-through", else: "text-green-600")
                ]}>
                  {clue.clue}
                </span>
              </div>
              <%= if clue.is_duplicate do %>
                <span class="text-red-500 text-sm">Duplicada</span>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @can_reveal do %>
          <button
            phx-click="reveal_clues"
            class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors text-lg"
          >
            Mostrar pistas al adivinador
          </button>
        <% else %>
          <div class="text-center text-gray-500 py-4">
            Esperando al creador para continuar...
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp guessing_phase(assigns) do
    is_guesser = assigns.player.id == assigns.game_state.guesser_id
    valid_clues = Enum.reject(assigns.game_state.revealed_clues, & &1.is_duplicate)
    assigns = assign(assigns, is_guesser: is_guesser, valid_clues: valid_clues)

    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6">
      <h2 class="text-2xl font-bold text-gray-800 mb-4 text-center">
        {if @is_guesser, do: "¡Tu turno de adivinar!", else: "Esperando respuesta..."}
      </h2>

      <div class="bg-indigo-50 rounded-xl p-4 mb-6">
        <p class="text-sm text-indigo-600 font-medium mb-3 text-center">Pistas válidas:</p>
        <div class="flex flex-wrap gap-2 justify-center">
          <%= for clue <- @valid_clues do %>
            <span class="px-4 py-2 bg-white rounded-full font-bold text-indigo-600 shadow">
              {clue.clue}
            </span>
          <% end %>
          <%= if Enum.empty?(@valid_clues) do %>
            <span class="text-gray-400">¡Todas las pistas fueron eliminadas!</span>
          <% end %>
        </div>
      </div>

      <%= if @is_guesser do %>
        <form phx-submit="submit_guess" class="space-y-4">
          <div>
            <label class="block text-gray-700 font-medium mb-2">Tu respuesta</label>
            <input
              type="text"
              name="guess"
              placeholder="¿Cuál es la palabra?"
              maxlength="50"
              class="w-full px-4 py-3 border-2 border-gray-200 rounded-lg focus:border-indigo-500 focus:outline-none text-lg"
              autofocus
              required
            />
          </div>

          <button
            type="submit"
            class="w-full px-4 py-3 bg-green-600 hover:bg-green-700 text-white font-medium rounded-lg transition-colors text-lg"
          >
            Adivinar
          </button>
        </form>
      <% else %>
        <div class="text-center text-gray-500 py-4">
          Esperando la respuesta del adivinador...
        </div>
      <% end %>
    </div>
    """
  end

  defp round_result(assigns) do
    is_owner = assigns.game_state.owner_session_id == assigns.session_id
    assigns = assign(assigns, is_owner: is_owner)

    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6 text-center">
      <%= if @game_state.last_result do %>
        <div class="text-6xl mb-4">🎉</div>
        <h2 class="text-3xl font-bold text-green-600 mb-2">¡Correcto!</h2>
      <% else %>
        <div class="text-6xl mb-4">😅</div>
        <h2 class="text-3xl font-bold text-red-500 mb-2">Incorrecto</h2>
      <% end %>

      <p class="text-gray-500 mb-2">La respuesta fue:</p>
      <p class="text-2xl font-bold text-indigo-600 uppercase mb-4">
        {@game_state.current_word}
      </p>

      <p class="text-gray-500 mb-6">
        Respuesta dada: <span class="font-medium">{@game_state.last_guess}</span>
      </p>

      <%= if @is_owner do %>
        <%= if @game_state.current_round >= @game_state.total_rounds do %>
          <button
            phx-click="next_round"
            class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors text-lg"
          >
            Ver resultados finales
          </button>
        <% else %>
          <button
            phx-click="next_round"
            class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors text-lg"
          >
            Siguiente ronda
          </button>
        <% end %>
      <% else %>
        <div class="text-gray-500 py-4">
          Esperando al creador para continuar...
        </div>
      <% end %>
    </div>
    """
  end

  defp game_finished(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-xl p-6 text-center">
      <div class="text-6xl mb-4">🏆</div>
      <h2 class="text-3xl font-bold text-gray-800 mb-4">¡Partida terminada!</h2>

      <div class="bg-indigo-50 rounded-xl p-6 mb-6">
        <p class="text-gray-500 mb-2">Puntuación final</p>
        <p class="text-5xl font-bold text-indigo-600">
          {@game_state.score} / {@game_state.total_rounds}
        </p>
      </div>

      <button
        phx-click="back_to_lobby"
        class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-lg transition-colors text-lg"
      >
        Volver al lobby
      </button>
    </div>
    """
  end

  defp players_list(assigns) do
    ~H"""
    <div class="bg-white/20 backdrop-blur rounded-xl p-4">
      <h3 class="text-white font-medium mb-3">Jugadores ({length(@game_state.players)})</h3>
      <div class="flex flex-wrap gap-2">
        <%= for player <- @game_state.players do %>
          <span class={[
            "px-3 py-1 rounded-full text-sm font-medium",
            if(player.is_guesser, do: "bg-yellow-400 text-yellow-900", else: "bg-white/30 text-white")
          ]}>
            {player.nickname}
            <%= if player.is_guesser do %>
              🎯
            <% end %>
          </span>
        <% end %>
      </div>
    </div>
    """
  end
end
