defmodule MmoLite.Players do
  @moduledoc """
  In-memory registry of every connected/known player, keyed by an opaque
  session token. No accounts, no persistence beyond process memory — a
  token that isn't found here means "treat as a brand-new player."
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

  @doc "Removes a player."
  def delete(token), do: GenServer.cast(__MODULE__, {:delete, token})

  @doc "Returns `{token, player}` pairs whose `last_seen` is older than `timeout_ms`."
  def stale(timeout_ms), do: GenServer.call(__MODULE__, {:stale, timeout_ms})

  # -- server ----------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:create, name}, _from, players) do
    token = generate_token()
    player = Player.new(token, name)
    {:reply, {token, player}, Map.put(players, token, player)}
  end

  @impl true
  def handle_call({:get, token}, _from, players) do
    {:reply, Map.get(players, token), players}
  end

  @impl true
  def handle_call({:update, token, fun}, _from, players) do
    case Map.fetch(players, token) do
      {:ok, player} ->
        updated = fun.(player)
        {:reply, updated, Map.put(players, token, updated)}

      :error ->
        {:reply, :error, players}
    end
  end

  @impl true
  def handle_call({:stale, timeout_ms}, _from, players) do
    now = System.monotonic_time(:millisecond)

    stale =
      Enum.filter(players, fn {_token, player} -> now - player.last_seen > timeout_ms end)

    {:reply, stale, players}
  end

  @impl true
  def handle_cast({:touch, token}, players) do
    players =
      Map.replace_lazy(players, token, fn player ->
        %{player | last_seen: System.monotonic_time(:millisecond)}
      end)

    {:noreply, players}
  end

  @impl true
  def handle_cast({:delete, token}, players), do: {:noreply, Map.delete(players, token)}

  defp generate_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
