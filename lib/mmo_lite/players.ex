defmodule MmoLite.Players do
  @moduledoc """
  In-memory registry of every connected/known player, keyed by an opaque
  session token. No accounts, no persistence beyond process memory — a
  token that isn't found here means "treat as a brand-new player."

  Players live in a protected ETS table: `get/1` reads it directly from the
  caller (floors and channels hit it on every move), while every write goes
  through this process so read-modify-write updates stay serialized.

  Also monitors each player's channel processes (see `attach/2`), so a
  player counts as connected for as long as any of their channels is
  alive, and only disconnected players are ever reported as stale.
  """

  use GenServer

  alias MmoLite.Player

  @table __MODULE__

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Creates a new player with a freshly generated token."
  def create(name), do: GenServer.call(__MODULE__, {:create, name})

  @doc "Looks up a player by token. Returns `nil` if unknown."
  def get(token) do
    case :ets.lookup(@table, token) do
      [{^token, player}] -> player
      [] -> nil
    end
  end

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
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:create, name}, _from, state) do
    token = generate_token()
    player = Player.new(token, name)
    :ets.insert(@table, {token, player})
    {:reply, {token, player}, state}
  end

  @impl true
  def handle_call({:update, token, fun}, _from, state) do
    case get(token) do
      nil ->
        {:reply, :error, state}

      player ->
        updated = fun.(player)
        :ets.insert(@table, {token, updated})
        {:reply, updated, state}
    end
  end

  @impl true
  def handle_call({:stale, timeout_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    connected = MapSet.new(Map.values(state.monitors))

    stale =
      :ets.foldl(
        fn {token, player} = entry, acc ->
          if not MapSet.member?(connected, token) and now - player.last_seen > timeout_ms,
            do: [entry | acc],
            else: acc
        end,
        [],
        @table
      )

    {:reply, stale, state}
  end

  @impl true
  def handle_cast({:touch, token}, state) do
    touch_player(token)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:attach, token, pid}, state) do
    ref = Process.monitor(pid)
    touch_player(token)
    {:noreply, put_in(state.monitors[ref], token)}
  end

  @impl true
  def handle_cast({:delete, token}, state) do
    :ets.delete(@table, token)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {token, monitors} = Map.pop(state.monitors, ref)
    # The reap timeout counts from the moment the player disconnected.
    touch_player(token)
    {:noreply, %{state | monitors: monitors}}
  end

  defp touch_player(token) do
    if player = get(token) do
      :ets.insert(@table, {token, %{player | last_seen: System.monotonic_time(:millisecond)}})
    end
  end

  defp generate_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
