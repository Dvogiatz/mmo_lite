defmodule MmoLite.Floor do
  @moduledoc """
  One running floor instance: its maze, its fixed-size monster pool, and
  the set of players currently on it. Started lazily by `MmoLite.FloorSupervisor`
  the first time a player enters a floor, and torn down after it's been
  empty for a while (spec allows discarding a floor's state once nobody's
  on it; re-entering later regenerates a fresh maze).

  All game-state mutation for players (level/hearts/equipment/position)
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

    # The maze never changes, so every cell's field of view is computed once
    # here rather than for every viewer on every broadcast.
    radius = Config.vision_radius()
    vision = Map.new(Map.keys(maze.cells), &{&1, Maze.visible_cells(maze, &1, radius)})

    {:ok, %{floor_num: floor_num, maze: maze, vision: vision, monsters: monsters, players: %{}}}
  end

  @impl true
  def handle_call({:join, token, channel_pid}, _from, state) do
    case Players.get(token) do
      nil ->
        {:reply, {:error, :unknown_player}, state}

      player ->
        state = put_in(state.players[token], channel_pid)
        position = player.position || place_player(state, token)

        # Broadcast first so everyone else already on this floor learns a
        # new player appeared nearby, then reply to the joiner directly.
        state = broadcast(state, [position], exclude: token)
        {:reply, {:ok, visible_state(state, token, position)}, state}
    end
  end

  @impl true
  def handle_call({:leave, token}, _from, state) do
    player = Players.get(token)
    state = remove_player(state, token, player && player.position)
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
            do_move(state, token, player, dest)

          monster ->
            if Player.evading?(player) do
              {:reply, result, state} = do_move(state, token, player, dest)
              {:reply, Map.put(result, :passed_through, monster_view(monster)), state}
            else
              handle_combat(state, token, player, monster, dest)
            end
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
        # Advancing floors is the only thing that refills hearts (per spec —
        # leveling up no longer does).
        Players.update(
          token,
          &%{&1 | floor: next_floor, position: nil, hearts: Player.max_hearts(&1)}
        )

        {:reply, {:ok, next_floor}, remove_player(state, token, player.position)}
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
    {:noreply, broadcast(state, [monster.position])}
  end

  @impl true
  def handle_info(:idle_teardown, state) do
    if map_size(state.players) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # A step onto an unoccupied cell — also used to walk straight through a
  # monster's cell while evading, since that's otherwise identical to a
  # plain move.
  defp do_move(state, token, player, dest) do
    Players.update(token, &%{&1 | position: dest})
    state = broadcast(state, [player.position, dest], include: token)
    {:reply, %{outcome: :moved, position: Wire.cell(dest)}, state}
  end

  # -- combat ----------------------------------------------------------------

  defp handle_combat(state, token, player, monster, dest) do
    player_power = Player.power(player)
    monster_power = Combat.monster_power(monster.level, monster.armor)
    {outcome, roll} = Combat.resolve(player_power, monster_power, Player.boots_bonus(player))

    if Combat.kill?(outcome) do
      handle_kill(state, token, player, monster, dest, outcome, roll)
    else
      handle_non_kill(state, token, player, outcome, roll)
    end
  end

  defp handle_kill(state, token, player, monster, dest, outcome, roll) do
    loot = Loot.generate(state.floor_num)
    # Decided against the *pre-kill* slot so the client can tell "found
    # nothing worth keeping" apart from "found nothing at all" — every kill
    # always drops something, but best-of-slot means it isn't always kept.
    equipped? = Loot.better?(Map.fetch!(player, loot.slot), loot)
    {new_level, levels_gained} = Leveling.apply_kill(player.level, monster.level)
    buff = %{expires_at: System.monotonic_time(:millisecond) + Config.killing_spree_duration_ms()}

    updated =
      Players.update(token, fn p ->
        %{p | position: dest, level: new_level, buff: buff} |> Player.equip(loot)
      end)

    state =
      state
      |> Map.update!(:monsters, &Map.delete(&1, monster.id))
      |> tap(fn _ ->
        Process.send_after(self(), :respawn_monster, Config.monster_respawn_ms())
      end)
      |> broadcast([player.position, dest], include: token)

    result = %{
      outcome: outcome,
      position: Wire.cell(dest),
      monster: monster_view(monster),
      loot: loot_view(loot),
      equipped: equipped?,
      roll: roll,
      level: new_level,
      hearts: updated.hearts,
      levels_gained: levels_gained
    }

    {:reply, result, state}
  end

  defp handle_non_kill(state, token, player, :flee, roll) do
    evasion_ms = Config.flee_immunity_ms()
    expires_at = System.monotonic_time(:millisecond) + evasion_ms
    Players.update(token, &%{&1 | evasion: %{expires_at: expires_at}})

    # Nothing on the floor itself changed, so nobody else needs an update.
    result = %{
      outcome: :flee,
      position: Wire.cell(player.position),
      roll: roll,
      evasion_ms: evasion_ms
    }

    {:reply, result, state}
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

      {:reply, result, remove_player(state, token, player.position)}
    else
      target_floor = max(player.floor - 1, 0)

      if target_floor == state.floor_num do
        safe_cell = spawn_cell(state)
        Players.update(token, &%{&1 | hearts: new_hearts, position: safe_cell})

        result = %{
          outcome: :loss,
          roll: roll,
          hearts: new_hearts,
          position: Wire.cell(safe_cell)
        }

        {:reply, result, broadcast(state, [player.position, safe_cell], include: token)}
      else
        Players.update(token, &%{&1 | hearts: new_hearts, floor: target_floor, position: nil})
        result = %{outcome: :loss, roll: roll, hearts: new_hearts, transfer_to: target_floor}
        {:reply, result, remove_player(state, token, player.position)}
      end
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp find_monster_at(state, position),
    do: Enum.find(Map.values(state.monsters), &(&1.position == position))

  # A random walkable cell that isn't currently sitting under a monster —
  # used for initial spawns, floor-transfer arrivals, and same-floor
  # heart-loss respawns, so players don't land on top of a forced fight.
  defp spawn_cell(state), do: Maze.random_cell(state.maze, &(find_monster_at(state, &1) != nil))

  # A new player, or one transferring in from another floor, has no position
  # yet — drop them on a random spawn cell rather than a fixed corner, so
  # players don't all funnel through the same starting corridor.
  defp place_player(state, token) do
    position = spawn_cell(state)
    Players.update(token, &%{&1 | position: position})
    position
  end

  defp player_positions(state) do
    for {_token, _pid, player} <- present_players(state), do: player.position
  end

  # Everyone connected to this floor, with their current state — fetched
  # once per broadcast rather than once per viewer.
  defp present_players(state) do
    for {token, pid} <- state.players,
        %Player{} = player <- [Players.get(token)],
        do: {token, pid, player}
  end

  # `position` is where the player was standing, so anyone who could see
  # them there learns they've gone.
  defp remove_player(state, token, position) do
    state = %{state | players: Map.delete(state.players, token)}

    if map_size(state.players) == 0 do
      Process.send_after(self(), :idle_teardown, Config.floor_idle_teardown_ms())
    end

    broadcast(state, List.wrap(position))
  end

  # Sends fresh visible state to every player on the floor who can see at
  # least one of the `changed` cells, plus `:include` (whose own view moved),
  # minus `:exclude` (who gets their state another way, e.g. a join reply).
  defp broadcast(state, changed, opts \\ []) do
    include = opts[:include]
    exclude = opts[:exclude]
    present = present_players(state)

    for {token, pid, player} <- present,
        token != exclude,
        token == include or sees_any?(state, player.position, changed) do
      send(pid, {:state_update, visible_state(state, token, player.position, present)})
    end

    state
  end

  defp sees_any?(state, origin, cells) do
    visible = vision(state, origin)
    Enum.any?(cells, &MapSet.member?(visible, &1))
  end

  # A player who hasn't been placed yet (nil position) sees nothing.
  defp vision(state, origin), do: Map.get(state.vision, origin, MapSet.new())

  defp visible_state(state, token, origin),
    do: visible_state(state, token, origin, present_players(state))

  defp visible_state(state, token, origin, present) do
    visible = vision(state, origin)

    monsters =
      state.monsters
      |> Map.values()
      |> Enum.filter(&MapSet.member?(visible, &1.position))
      |> Enum.map(&monster_view/1)

    players =
      for {other, _pid, player} <- present,
          other != token,
          MapSet.member?(visible, player.position),
          do: player_view(player)

    %{
      floor: state.floor_num,
      origin: Wire.cell(origin),
      tiles: Wire.tiles(Maze.tiles(state.maze, visible)),
      door: if(MapSet.member?(visible, state.maze.door), do: Wire.cell(state.maze.door)),
      door_level: Config.door_level_requirement(state.floor_num),
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

  defp loot_view(loot), do: Map.take(loot, [:id, :slot, :name, :tier, :value])

  defp player_view(player),
    do: %{name: player.name, position: Wire.cell(player.position), level: player.level}
end
