defmodule MmoLite.FloorTest do
  # Exercises the real Players/FloorSupervisor/Floor singletons started by
  # the application — not async, since floor numbers are shared global state.
  use ExUnit.Case, async: false

  alias MmoLite.{Config, Floor, FloorSupervisor, Loot, Maze, Monsters, Players, Wire}

  setup do
    # A random-ish floor number per test avoids collisions with any other
    # test (or a leftover process) using the same floor.
    floor_num = System.unique_integer([:positive, :monotonic])
    {token, _player} = Players.create("Tester")
    FloorSupervisor.ensure_started(floor_num)
    {:ok, floor: floor_num, token: token}
  end

  test "join returns a JSON-encodable visible state", %{floor: floor, token: token} do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, visible} = Floor.join(floor, token, self())

    assert visible.floor == floor
    assert visible.door_level == Config.door_level_requirement(floor)
    assert is_list(visible.origin)
    assert Jason.encode!(visible)
  end

  test "move results are JSON-encodable for every outcome shape", %{floor: floor, token: token} do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    result = Floor.move(floor, token, :north)
    assert Jason.encode!(result)
    assert result.outcome in [:blocked, :moved, :win, :upset_win, :flee, :loss]

    if position = result[:position] do
      assert is_list(position)
    end
  end

  test "an unknown token is refused and not registered on the floor", %{floor: floor} do
    assert {:error, :unknown_player} = Floor.join(floor, "no-such-token", self())

    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    refute Map.has_key?(:sys.get_state(pid).players, "no-such-token")
  end

  test "a player standing elsewhere than the door cannot enter it", %{floor: floor, token: token} do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    assert {:error, :not_at_door} = Floor.enter_door(floor, token)
  end

  test "the door is locked below the floor's level requirement and opens above it", %{
    floor: floor,
    token: token
  } do
    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    %{maze: maze} = :sys.get_state(pid)
    required = Config.door_level_requirement(floor)

    Players.update(token, &%{&1 | floor: floor, position: maze.door, level: required - 1})
    {:ok, _visible} = Floor.join(floor, token, self())

    assert {:error, :level_too_low, ^required} = Floor.enter_door(floor, token)

    Players.update(token, &%{&1 | level: required})
    assert {:ok, next_floor} = Floor.enter_door(floor, token)
    assert next_floor == floor + 1
    assert Players.get(token).floor == next_floor
  end

  test "advancing through the door fully heals hearts, but a level bump alone does not", %{
    floor: floor,
    token: token
  } do
    required = Config.door_level_requirement(floor)
    Players.update(token, &%{&1 | floor: floor, level: required, hearts: 1})
    {:ok, _visible} = Floor.join(floor, token, self())

    Players.update(token, fn p -> %{p | level: p.level + 5} end)
    assert Players.get(token).hearts == 1

    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    %{maze: maze} = :sys.get_state(pid)
    Players.update(token, &%{&1 | position: maze.door})

    assert {:ok, _next_floor} = Floor.enter_door(floor, token)
    player = Players.get(token)
    assert player.hearts == MmoLite.Player.max_hearts(player)
  end

  test "leave removes the player and does not crash on an empty floor", %{
    floor: floor,
    token: token
  } do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    assert :ok = Floor.leave(floor, token)
  end

  test "an existing player on the floor is notified when someone new joins nearby", %{
    floor: floor,
    token: token
  } do
    # Pin both to the same cell — spawns are random now, so without this
    # they might land outside each other's vision radius.
    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    %{maze: maze} = :sys.get_state(pid)

    Players.update(token, &%{&1 | floor: floor, position: maze.entry})
    {:ok, _visible} = Floor.join(floor, token, self())
    flush_mailbox()

    {other_token, _other_player} = Players.create("Newcomer")
    Players.update(other_token, &%{&1 | floor: floor, position: maze.entry})
    {:ok, _visible} = Floor.join(floor, other_token, self())

    assert_receive {:state_update, %{players: [%{name: "Newcomer"}]}}
  end

  test "players who can't see a move are not sent an update", %{floor: floor, token: token} do
    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    %{maze: maze} = :sys.get_state(pid)
    # No monsters, so the move can't become a fight that respawns anyone.
    :sys.replace_state(pid, &%{&1 | monsters: %{}})

    # The door is the cell farthest from the entry, well out of vision range.
    Players.update(token, &%{&1 | floor: floor, position: maze.entry})
    {:ok, _visible} = Floor.join(floor, token, self())

    {far_token, _player} = Players.create("Faraway")
    Players.update(far_token, &%{&1 | floor: floor, position: maze.door})
    {:ok, _visible} = Floor.join(floor, far_token, spawn(fn -> Process.sleep(:infinity) end))
    flush_mailbox()

    dir =
      Enum.find([:north, :south, :east, :west], &match?({:ok, _}, Maze.move(maze, maze.door, &1)))

    assert %{outcome: :moved} = Floor.move(floor, far_token, dir)
    # Any update would have been sent before the move's reply.
    refute_received {:state_update, _}
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  test "walking into a far-weaker monster is an outright win with loot/level-up", %{
    floor: floor,
    token: token
  } do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    {dir, monster_pos} = place_monster(floor, token, level: 0, armor: 0)

    result = Floor.move(floor, token, dir)

    assert result.outcome == :win
    assert result.position == Wire.cell(monster_pos)
    assert result.levels_gained >= 1
    assert result.loot.slot in [:weapon, :armor, :boots]

    player = Players.get(token)
    assert player.level > 1
    assert player.hearts >= Config.starting_hearts()
  end

  test "fleeing grants a temporary evasion buff that lets you walk through monsters", %{
    floor: floor,
    token: token
  } do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    # Epic boots (bonus +4) make a flee the overwhelming favourite on an
    # outmatched roll (only a roll of 1 still loses), so this reaches a
    # flee reliably in a handful of attempts.
    Players.update(
      token,
      &%{&1 | boots: %Loot{slot: :boots, tier: :epic, value: 4, name: "Test Greaves"}}
    )

    # A loss transfers the player to `floor - 1` (this test's floor number
    # is a large unique integer, never 0, so that's always a genuine
    # transfer) — the loop has to follow it, same as the full-reset test
    # below, rather than keep hammering a floor the player has left.
    flee_result =
      Enum.reduce_while(1..50, floor, fn _attempt, current_floor ->
        overwhelming_power = MmoLite.Player.power(Players.get(token)) + 1000
        {dir, _pos} = place_monster(current_floor, token, level: overwhelming_power, armor: 0)
        result = Floor.move(current_floor, token, dir)

        cond do
          result.outcome == :flee ->
            {:halt, result}

          next_floor = result[:transfer_to] ->
            FloorSupervisor.ensure_started(next_floor)
            {:ok, _visible} = Floor.join(next_floor, token, self())
            {:cont, next_floor}

          true ->
            {:cont, current_floor}
        end
      end)

    assert is_map(flee_result)
    assert flee_result.outcome == :flee
    assert flee_result.evasion_ms == Config.flee_immunity_ms()
    assert MmoLite.Player.evading?(Players.get(token))
  end

  test "evading, walking into a monster passes through it instead of fighting", %{
    floor: floor,
    token: token
  } do
    Players.update(token, &%{&1 | floor: floor})
    {:ok, _visible} = Floor.join(floor, token, self())

    Players.update(
      token,
      &%{&1 | evasion: %{expires_at: System.monotonic_time(:millisecond) + 10_000}}
    )

    before = Players.get(token)
    {dir, monster_pos} = place_monster(floor, token, level: 999, armor: 0)

    result = Floor.move(floor, token, dir)

    assert result.outcome == :moved
    assert result.position == Wire.cell(monster_pos)
    assert result.passed_through.level == 999

    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    # The monster wasn't fought, so it's still standing where it was.
    assert %{position: ^monster_pos} =
             :sys.get_state(pid).monsters |> Map.values() |> Enum.find(&(&1.level == 999))

    player = Players.get(token)
    assert player.position == monster_pos
    assert player.level == before.level
    assert player.hearts == before.hearts
  end

  test "running out of hearts triggers a full reset to floor 0 with equipment lost", %{
    floor: floor,
    token: token
  } do
    Players.update(token, &%{&1 | floor: floor, hearts: 1})
    {:ok, _visible} = Floor.join(floor, token, self())

    # An upset win (rolling a 6) grants loot mid-loop; if that loot is a
    # better armor than currently equipped, it also grants a few bonus
    # hearts (see Player.equip/2), so a later loss might not zero hearts
    # out immediately — it can instead transfer the player to an easier
    # floor (correct per spec). The loop has to follow the player across
    # that transfer rather than keep hammering the original floor, or it
    # just orphans them.
    #
    # It also has to keep re-deriving the monster's power from the
    # player's *current* power (rather than a fixed stat) — weapon damage
    # scales with this test's floor number, which is a large globally
    # unique integer, so a lucky early upset-win could otherwise hand the
    # player enough weapon power to out-power a fixed monster forever and
    # the loop would never see another loss.
    # Armor's hearts bonus saturates at +5 once the best possible armor
    # (value 5) is equipped, after which every loss only ever costs 1 with
    # no further gains — so this needs real headroom, not just a handful
    # of attempts, to reliably reach 0. 300 gives a huge margin over the
    # ~15-attempt expectation.
    result =
      Enum.reduce_while(1..300, floor, fn _attempt, current_floor ->
        overwhelming_power = MmoLite.Player.power(Players.get(token)) + 1000
        {dir, _pos} = place_monster(current_floor, token, level: overwhelming_power, armor: 0)
        result = Floor.move(current_floor, token, dir)
        # A flee grants temporary immunity (walk through monsters instead of
        # fighting) — clear it after every attempt so this loop keeps
        # forcing real fights instead of stalling on pass-throughs.
        Players.update(token, &%{&1 | evasion: nil})

        cond do
          result[:full_reset] ->
            {:halt, result}

          next_floor = result[:transfer_to] ->
            FloorSupervisor.ensure_started(next_floor)
            {:ok, _visible} = Floor.join(next_floor, token, self())
            {:cont, next_floor}

          true ->
            {:cont, current_floor}
        end
      end)

    assert is_map(result)
    assert result.outcome == :loss
    assert result.full_reset
    assert result.transfer_to == 0

    player = Players.get(token)
    assert player.floor == 0
    assert player.hearts == Config.starting_hearts()
    assert player.weapon == nil
    assert player.armor == nil
    assert player.boots == Loot.starter_boots()
  end

  # Places a fresh monster one step away from the player's *current*
  # position (in whichever direction happens to be open) and returns that
  # direction plus the monster's cell, so the caller can move into it.
  defp place_monster(floor, token, level: level, armor: armor) do
    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, floor)
    %{maze: maze} = :sys.get_state(pid)
    origin = Players.get(token).position

    {dir, dest} =
      Enum.find_value([:north, :south, :east, :west], fn dir ->
        case Maze.move(maze, origin, dir) do
          {:ok, dest} -> {dir, dest}
          :blocked -> nil
        end
      end)

    monster = %Monsters{
      id: System.unique_integer([:positive]),
      level: level,
      armor: armor,
      position: dest
    }

    :sys.replace_state(pid, fn state ->
      # Evict anything already sitting at `dest` (e.g. from the floor's
      # initial pool) — otherwise find_monster_at/2 could pick that one up
      # instead of the one we just placed, since both share a cell.
      monsters =
        state.monsters
        |> Enum.reject(fn {_id, m} -> m.position == dest end)
        |> Map.new()
        |> Map.put(monster.id, monster)

      %{state | monsters: monsters}
    end)

    {dir, dest}
  end
end
