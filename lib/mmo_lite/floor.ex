defmodule MmoLite.Floor do
  @moduledoc """
  One running floor instance: its maze, its fixed-size monster pool, and
  the set of players currently on it. Started lazily by `MmoLite.FloorSupervisor`
  the first time a player enters a floor, and torn down after it's been
  empty for a while (spec allows discarding a floor's state once nobody's
  on it; re-entering later regenerates a fresh maze).

  All game-state mutation for players (level/xp/hearts/equipment/position)
  goes through `MmoLite.Players`, which stays the single source of truth —
  this process only tracks *who is currently connected here* (token =>
  channel pid) and the floor's own maze/monster state, entirely
  event-driven off player moves (no periodic tick — monsters don't move on
  their own).
  """

  use GenServer

  alias MmoLite.{Combat, Config, Leveling, Loot, Maze, Monsters, Player, Players, Wire}

  # -- client API --------------------------------------------------------

  def start_link(floor_num) do
    GenServer.start_link(__MODULE__, floor_num, name: via(floor_num))
  end

  def child_spec(floor_num) do
    %{
      id: {__MODULE__, floor_num},
      start: {__MODULE__, :start_link, [floor_num]},
      restart: :temporary
    }
  end

  @doc "Registers `token`/`channel_pid` as present on this floor; returns the player's initial visible state."
  def join(floor_num, token, channel_pid),
    do: GenServer.call(via(floor_num), {:join, token, channel_pid})

  @doc "Removes `token` from this floor (no reply needed)."
  def leave(floor_num, token), do: GenServer.call(via(floor_num), {:leave, token})

  @doc """
  Attempts to move `token` one cell in `dir`. Returns a result map describing
  what happened — see `MmoLiteWeb.GameChannel` for how each `:outcome` is
  handled, including the `:transfer_to` floor-change cases.
  """
  def move(floor_num, token, dir), do: GenServer.call(via(floor_num), {:move, token, dir})

  @doc "Attempts to use the floor's door. Requires standing on it and meeting the level requirement."
  def enter_door(floor_num, token), do: GenServer.call(via(floor_num), {:enter_door, token})

  defp via(floor_num), do: {:via, Registry, {MmoLite.FloorRegistry, floor_num}}

  # -- server --------------------------------------------------------------

  @impl true
  def init(floor_num) do
    maze = Maze.generate(Config.maze_width(), Config.maze_height())
    monsters = floor_num |> Monsters.generate_pool(maze) |> Map.new(&{&1.id, &1})
    {:ok, %{floor_num: floor_num, maze: maze, monsters: monsters, players: %{}}}
  end

  @impl true
  def handle_call({:join, token, channel_pid}, _from, state) do
    state = put_in(state.players[token], channel_pid)

    case Players.get(token) do
      nil ->
        {:reply, {:error, :unknown_player}, state}

      player ->
        # Broadcast first so everyone else already on this floor learns a
        # new player appeared nearby, then reply to the joiner directly.
        state = broadcast(state)
        {:reply, {:ok, visible_state(state, token, player.position)}, state}
    end
  end

  @impl true
  def handle_call({:leave, token}, _from, state) do
    state = remove_player(state, token)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:move, token, dir}, _from, state) do
    player = Players.get(token)

    case Maze.move(state.maze, player.position, dir) do
      :blocked ->
        {:reply, %{outcome: :blocked}, state}

      {:ok, dest} ->
        case find_monster_at(state, dest) do
          nil ->
            Players.update(token, &%{&1 | position: dest})
            {:reply, %{outcome: :moved, position: Wire.cell(dest)}, broadcast(state)}

          monster ->
            handle_combat(state, token, player, monster, dest)
        end
    end
  end

  @impl true
  def handle_call({:enter_door, token}, _from, state) do
    player = Players.get(token)
    required = Config.door_level_requirement(state.floor_num)

    cond do
      player.position != state.maze.door ->
        {:reply, {:error, :not_at_door}, state}

      player.level < required ->
        {:reply, {:error, :level_too_low, required}, state}

      true ->
        next_floor = state.floor_num + 1
        Players.update(token, &%{&1 | floor: next_floor, position: {0, 0}})
        {:reply, {:ok, next_floor}, remove_player(state, token)}
    end
  end

  @impl true
  def handle_info(:respawn_monster, state) do
    monster =
      Monsters.generate(
        state.floor_num,
        Monsters.respawn_location(state.maze, player_positions(state))
      )

    state = %{state | monsters: Map.put(state.monsters, monster.id, monster)}
    {:noreply, broadcast(state)}
  end

  @impl true
  def handle_info(:idle_teardown, state) do
    if map_size(state.players) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # -- combat ----------------------------------------------------------------

  defp handle_combat(state, token, player, monster, dest) do
    player_power = Player.power(player)
    monster_power = Combat.monster_power(monster.level, monster.armor)
    {outcome, roll} = Combat.resolve(player_power, monster_power)

    if Combat.kill?(outcome) do
      handle_kill(state, token, player, monster, dest, outcome, roll)
    else
      handle_non_kill(state, token, player, outcome, roll)
    end
  end

  defp handle_kill(state, token, player, monster, dest, outcome, roll) do
    loot = Loot.generate(state.floor_num)

    {new_level, new_xp, new_hearts, levels_gained} =
      Leveling.apply_kill(player.level, player.xp, player.hearts, monster.level)

    buff = %{expires_at: System.monotonic_time(:millisecond) + Config.killing_spree_duration_ms()}

    Players.update(token, fn p ->
      %{
        p
        | position: dest,
          level: new_level,
          xp: new_xp,
          hearts: new_hearts,
          equipment: [loot | p.equipment],
          buff: buff
      }
    end)

    state =
      state
      |> Map.update!(:monsters, &Map.delete(&1, monster.id))
      |> tap(fn _ ->
        Process.send_after(self(), :respawn_monster, Config.monster_respawn_ms())
      end)
      |> broadcast()

    result = %{
      outcome: outcome,
      position: Wire.cell(dest),
      monster: monster_view(monster),
      loot: loot_view(loot),
      roll: roll,
      level: new_level,
      xp: new_xp,
      hearts: new_hearts,
      levels_gained: levels_gained
    }

    {:reply, result, state}
  end

  defp handle_non_kill(state, _token, player, :flee, roll) do
    {:reply, %{outcome: :flee, position: Wire.cell(player.position), roll: roll}, broadcast(state)}
  end

  defp handle_non_kill(state, token, player, :loss, roll) do
    new_hearts = player.hearts - 1

    if new_hearts <= 0 do
      reset = Player.full_reset(%{player | hearts: 0})
      Players.update(token, fn _ -> reset end)

      result = %{
        outcome: :loss,
        roll: roll,
        full_reset: true,
        transfer_to: reset.floor,
        hearts: reset.hearts,
        level: reset.level
      }

      {:reply, result, remove_player(state, token)}
    else
      target_floor = max(player.floor - 1, 0)

      if target_floor == state.floor_num do
        Players.update(token, &%{&1 | hearts: new_hearts, position: state.maze.entry})

        result = %{
          outcome: :loss,
          roll: roll,
          hearts: new_hearts,
          position: Wire.cell(state.maze.entry)
        }

        {:reply, result, broadcast(state)}
      else
        Players.update(token, &%{&1 | hearts: new_hearts, floor: target_floor, position: {0, 0}})
        result = %{outcome: :loss, roll: roll, hearts: new_hearts, transfer_to: target_floor}
        {:reply, result, remove_player(state, token)}
      end
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp find_monster_at(state, position),
    do: Enum.find(Map.values(state.monsters), &(&1.position == position))

  defp player_positions(state) do
    state.players
    |> Map.keys()
    |> Enum.map(&Players.get/1)
    |> Enum.filter(& &1)
    |> Enum.map(& &1.position)
  end

  defp remove_player(state, token) do
    state = %{state | players: Map.delete(state.players, token)}

    if map_size(state.players) == 0 do
      Process.send_after(self(), :idle_teardown, Config.floor_idle_teardown_ms())
    end

    broadcast(state)
  end

  defp broadcast(state) do
    Enum.each(state.players, fn {token, pid} ->
      case Players.get(token) do
        nil -> :ok
        player -> send(pid, {:state_update, visible_state(state, token, player.position)})
      end
    end)

    state
  end

  defp visible_state(state, token, origin) do
    visible = Maze.visible_cells(state.maze, origin, Config.vision_radius())

    monsters =
      state.monsters
      |> Map.values()
      |> Enum.filter(&MapSet.member?(visible, &1.position))
      |> Enum.map(&monster_view/1)

    players =
      state.players
      |> Map.keys()
      |> Enum.reject(&(&1 == token))
      |> Enum.map(&Players.get/1)
      |> Enum.filter(&(&1 && MapSet.member?(visible, &1.position)))
      |> Enum.map(&player_view/1)

    %{
      floor: state.floor_num,
      origin: Wire.cell(origin),
      tiles: Wire.tiles(Maze.tiles(state.maze, MapSet.to_list(visible))),
      door: if(MapSet.member?(visible, state.maze.door), do: Wire.cell(state.maze.door)),
      monsters: monsters,
      players: players
    }
  end

  defp monster_view(monster) do
    %{
      id: monster.id,
      position: Wire.cell(monster.position),
      level: monster.level,
      armor: monster.armor
    }
  end

  defp loot_view(loot), do: Map.take(loot, [:id, :name, :damage, :tier])

  defp player_view(player),
    do: %{name: player.name, position: Wire.cell(player.position), level: player.level}
end
