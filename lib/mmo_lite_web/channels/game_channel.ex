defmodule MmoLiteWeb.GameChannel do
  use MmoLiteWeb, :channel

  alias MmoLite.{Config, Floor, FloorSupervisor, Player, Players, Wire}

  @impl true
  def join("game:play", params, socket) do
    with {:ok, token, player} <- resolve_player(params) do
      FloorSupervisor.ensure_started(player.floor)
      {:ok, visible} = Floor.join(player.floor, token, self())
      Players.touch(token)

      socket = assign(socket, :token, token)
      {:ok, join_reply(player, visible), socket}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_in("move", %{"dir" => dir}, socket) do
    case parse_dir(dir) do
      {:ok, dir_atom} ->
        token = socket.assigns.token
        floor = Players.get(token).floor
        result = Floor.move(floor, token, dir_atom)
        maybe_transfer(token, result)
        Players.touch(token)
        push(socket, "player_update", player_update_payload(token))
        {:reply, {:ok, result}, socket}

      :error ->
        {:reply, {:error, %{reason: :invalid_direction}}, socket}
    end
  end

  @impl true
  def handle_in("enter_door", _params, socket) do
    token = socket.assigns.token
    floor = Players.get(token).floor

    case Floor.enter_door(floor, token) do
      {:ok, next_floor} ->
        FloorSupervisor.ensure_started(next_floor)
        {:ok, visible} = Floor.join(next_floor, token, self())
        push(socket, "player_update", player_update_payload(token))
        {:reply, {:ok, %{floor: next_floor, visible: visible}}, socket}

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
      name: player.name,
      floor: player.floor,
      position: Wire.cell(player.position),
      level: player.level,
      xp: player.xp,
      hearts: player.hearts,
      max_hearts: Config.max_hearts(),
      equipment: Enum.map(player.equipment, &equipment_view/1),
      buff: buff_view(player),
      visible: visible
    }
  end

  # -- move/door helpers -------------------------------------------------

  defp parse_dir("up"), do: {:ok, :north}
  defp parse_dir("down"), do: {:ok, :south}
  defp parse_dir("left"), do: {:ok, :west}
  defp parse_dir("right"), do: {:ok, :east}
  defp parse_dir(_), do: :error

  defp maybe_transfer(token, %{transfer_to: next_floor}) do
    FloorSupervisor.ensure_started(next_floor)
    {:ok, visible} = Floor.join(next_floor, token, self())
    send(self(), {:state_update, visible})
  end

  defp maybe_transfer(_token, _result), do: :ok

  defp player_update_payload(token) do
    player = Players.get(token)

    %{
      level: player.level,
      xp: player.xp,
      hearts: player.hearts,
      max_hearts: Config.max_hearts(),
      equipment: Enum.map(player.equipment, &equipment_view/1),
      buff: buff_view(player),
      floor: player.floor,
      position: Wire.cell(player.position)
    }
  end

  defp equipment_view(item), do: Map.take(item, [:id, :name, :damage, :tier])

  defp buff_view(player) do
    if Player.buff_active?(player) do
      remaining_ms = player.buff.expires_at - System.monotonic_time(:millisecond)
      %{remaining_ms: max(remaining_ms, 0), damage: Config.killing_spree_damage()}
    end
  end
end
