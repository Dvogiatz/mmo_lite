defmodule MmoLite.Players do
  @moduledoc """
  In-memory registry of every connected/known player, keyed by an opaque
  session token. No accounts, no persistence beyond process memory — a
  token that isn't found here means "treat as a brand-new player."

  Also monitors each player's channel processes (see `attach/2`), so a
  player counts as connected for as long as any of their channels is
  alive, and only disconnected players are ever reported as stale.
  """

  use GenServer

  alias MmoLite.Player

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Creates a new player with a freshly generated token."
  def create(name), do: GenServer.call(__MODULE__, {:create, name})

  @doc "Looks up a player by token. Returns `nil` if unknown."
  def get(token), do: GenServer.call(__MODULE__, {:get, token})

  @doc "Updates a known player via `fun.(player) :: player`. Returns the updated player or `:error`."
  def update(token, fun), do: GenServer.call(__MODULE__, {:update, token, fun})

  @doc "Refreshes a player's last-seen timestamp (used on reconnect/activity)."
  def touch(token), do: GenServer.cast(__MODULE__, {:touch, token})

  @doc """
  Marks `token` as connected through `pid` (its channel process) until that
  process exits; its last-seen timestamp is refreshed when it does.
  """
  def attach(token, pid), do: GenServer.cast(__MODULE__, {:attach, token, pid})

  @doc "Removes a player."
  def delete(token), do: GenServer.cast(__MODULE__, {:delete, token})

  @doc "Returns `{token, player}` pairs with no live channel whose `last_seen` is older than `timeout_ms`."
  def stale(timeout_ms), do: GenServer.call(__MODULE__, {:stale, timeout_ms})

  # -- server ----------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %{players: %{}, monitors: %{}}}

  @impl true
  def handle_call({:create, name}, _from, state) do
    token = generate_token()
    player = Player.new(token, name)
    {:reply, {token, player}, put_in(state.players[token], player)}
  end

  @impl true
  def handle_call({:get, token}, _from, state) do
    {:reply, Map.get(state.players, token), state}
  end

  @impl true
  def handle_call({:update, token, fun}, _from, state) do
    case Map.fetch(state.players, token) do
      {:ok, player} ->
        updated = fun.(player)
        {:reply, updated, put_in(state.players[token], updated)}

      :error ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:stale, timeout_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    connected = MapSet.new(Map.values(state.monitors))

    stale =
      Enum.filter(state.players, fn {token, player} ->
        not MapSet.member?(connected, token) and now - player.last_seen > timeout_ms
      end)

    {:reply, stale, state}
  end

  @impl true
  def handle_cast({:touch, token}, state), do: {:noreply, touch_player(state, token)}

  @impl true
  def handle_cast({:attach, token, pid}, state) do
    ref = Process.monitor(pid)
    {:noreply, touch_player(put_in(state.monitors[ref], token), token)}
  end

  @impl true
  def handle_cast({:delete, token}, state),
    do: {:noreply, %{state | players: Map.delete(state.players, token)}}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {token, monitors} = Map.pop(state.monitors, ref)
    # The reap timeout counts from the moment the player disconnected.
    {:noreply, touch_player(%{state | monitors: monitors}, token)}
  end

  defp touch_player(state, token) do
    players =
      Map.replace_lazy(state.players, token, fn player ->
        %{player | last_seen: System.monotonic_time(:millisecond)}
      end)

    %{state | players: players}
  end

  defp generate_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
