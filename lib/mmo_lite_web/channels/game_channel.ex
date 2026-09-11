defmodule MmoLiteWeb.GameChannel do
  use MmoLiteWeb, :channel

  alias MmoLite.{Config, Floor, FloorSupervisor, Player, Players, Wire}

  @impl true
  def join("game:play", params, socket) do
    with {:ok, token, player} <- resolve_player(params) do
      FloorSupervisor.ensure_started(player.floor)
      {:ok, visible} = Floor.join(player.floor, token, self())
      Players.attach(token, self())

      socket = assign(socket, :token, token)
      {:ok, join_reply(player, visible), socket}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_in("move", %{"dir" => dir}, socket) do
    now = System.monotonic_time(:millisecond)

    # Checked before touching Players/Floor, so rejected moves cost nothing.
    with :ok <- check_move_cooldown(socket, now),
         {:ok, dir_atom} <- parse_dir(dir) do
      token = socket.assigns.token
      floor = Players.get(token).floor
      result = Floor.move(floor, token, dir_atom)
      maybe_transfer(socket, token, result)
      Players.touch(token)

      # Only fights and floor transfers change stats — a plain step doesn't.
      if result.outcome not in [:moved, :blocked],
        do: push(socket, "player_update", player_update_payload(token))

      {:reply, {:ok, result}, assign(socket, :last_move_at, now)}
    else
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("enter_door", _params, socket) do
    token = socket.assigns.token
    floor = Players.get(token).floor

    case Floor.enter_door(floor, token) do
      {:ok, next_floor} ->
        enter_floor(socket, token, next_floor)
        push(socket, "player_update", player_update_payload(token))
        {:reply, {:ok, %{floor: next_floor}}, socket}

      {:error, :level_too_low, required} ->
        {:reply, {:error, %{reason: "level_too_low", required: required}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_info({:state_update, payload}, socket) do
    push(socket, "state_update", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:roster_update, payload}, socket) do
    push(socket, "roster_update", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    with token when is_binary(token) <- socket.assigns[:token],
         %Player{} = player <- Players.get(token),
         [{_pid, _}] <- Registry.lookup(MmoLite.FloorRegistry, player.floor) do
      Floor.leave(player.floor, token)
    end

    :ok
  end

  # -- join/session resolution -----------------------------------------------

  defp resolve_player(%{"token" => token}) when is_binary(token) and token != "" do
    case Players.get(token) do
      nil -> {:error, "unknown_token"}
      player -> {:ok, token, player}
    end
  end

  defp resolve_player(%{"name" => name}) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, 20) do
      "" ->
        {:error, "name_required"}

      trimmed ->
        {token, player} = Players.create(trimmed)
        {:ok, token, player}
    end
  end

  defp resolve_player(_params), do: {:error, "name_required"}

  defp join_reply(player, visible) do
    %{
      token: player.token,
      id: player.id,
      name: player.name,
      floor: player.floor,
      position: Wire.cell(player.position),
      level: player.level,
      hearts: player.hearts,
      max_hearts: Player.max_hearts(player),
      equipment: equipment_view(player),
      buff: buff_view(player),
      evasion: evasion_view(player),
      move_cooldown_ms: Config.move_cooldown_ms(),
      visible: visible
    }
  end

  # -- move/door helpers -------------------------------------------------

  defp check_move_cooldown(socket, now) do
    last = socket.assigns[:last_move_at]
    if last && now - last < Config.move_cooldown_ms(), do: {:error, :too_fast}, else: :ok
  end

  defp parse_dir("up"), do: {:ok, :north}
  defp parse_dir("down"), do: {:ok, :south}
  defp parse_dir("left"), do: {:ok, :west}
  defp parse_dir("right"), do: {:ok, :east}
  defp parse_dir(_), do: {:error, :invalid_direction}

  defp maybe_transfer(socket, token, %{transfer_to: next_floor}),
    do: enter_floor(socket, token, next_floor)

  defp maybe_transfer(_socket, _token, _result), do: :ok

  # Joins `floor` (starting it if needed) and pushes the arriving player's
  # first view of it — the floor itself only notifies players already there.
  defp enter_floor(socket, token, floor) do
    FloorSupervisor.ensure_started(floor)
    {:ok, visible} = Floor.join(floor, token, self())
    push(socket, "state_update", visible)
  end

  defp player_update_payload(token) do
    player = Players.get(token)

    %{
      level: player.level,
      hearts: player.hearts,
      max_hearts: Player.max_hearts(player),
      equipment: equipment_view(player),
      buff: buff_view(player),
      evasion: evasion_view(player),
      floor: player.floor,
      position: Wire.cell(player.position)
    }
  end

  # One entry per slot (weapon/armor/boots), `nil` where nothing's equipped —
  # not a list, since best-of-slot means there's at most one item per slot.
  defp equipment_view(player) do
    %{
      weapon: item_view(player.weapon),
      armor: item_view(player.armor),
      boots: item_view(player.boots)
    }
  end

  defp item_view(nil), do: nil
  defp item_view(item), do: Map.take(item, [:id, :name, :tier, :value])

  defp buff_view(player) do
    if Player.buff_active?(player) do
      remaining_ms = player.buff.expires_at - System.monotonic_time(:millisecond)
      %{remaining_ms: max(remaining_ms, 0), damage: Config.killing_spree_damage()}
    end
  end

  defp evasion_view(player) do
    if Player.evading?(player) do
      remaining_ms = player.evasion.expires_at - System.monotonic_time(:millisecond)
      %{remaining_ms: max(remaining_ms, 0)}
    end
  end
end
