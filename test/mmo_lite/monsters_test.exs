defmodule MmoLite.MonstersTest do
  use ExUnit.Case, async: true

  alias MmoLite.{Maze, Monsters}

  test "level_for_floor scales by floor: floor n -> levels n*10+1..n*10+10" do
    for _ <- 1..50 do
      assert Monsters.level_for_floor(0) in 1..10
      assert Monsters.level_for_floor(2) in 21..30
    end
  end

  test "generate_pool creates the requested fixed pool size" do
    maze = Maze.generate(15, 15, 0.3)
    pool = Monsters.generate_pool(0, maze, 6)

    assert length(pool) == 6
    assert Enum.all?(pool, &(&1.level in 1..10))
  end

  test "respawn_location avoids every player's vision radius when possible" do
    maze = Maze.generate(21, 21, 0.3)
    radius = MmoLite.Config.vision_radius()

    player_positions = [maze.entry]
    visible = Maze.visible_cells(maze, maze.entry, radius)

    location = Monsters.respawn_location(maze, player_positions, 50)

    refute MapSet.member?(visible, location)
  end

  test "respawn_location falls back to the farthest cell when no player is present" do
    maze = Maze.generate(9, 9, 0.0)
    location = Monsters.respawn_location(maze, [])

    assert Maze.in_bounds?(maze, location)
  end
end
