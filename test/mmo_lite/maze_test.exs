defmodule MmoLite.MazeTest do
  use ExUnit.Case, async: true

  alias MmoLite.Maze

  test "generates a maze where every cell is reachable from the entry" do
    maze = Maze.generate(11, 11, 0.0)
    reachable = Maze.distances_from(maze, maze.entry)

    all_cells = for x <- 0..10, y <- 0..10, do: {x, y}
    assert Enum.all?(all_cells, &Map.has_key?(reachable, &1))
  end

  test "a maze with 0% braiding is a perfect maze (every non-entry cell has exactly one path in)" do
    maze = Maze.generate(9, 9, 0.0)

    # In a perfect maze, the number of open (directed) connections equals
    # 2 * (number of cells - 1) since it's a spanning tree.
    total_open =
      maze.cells
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()

    cell_count = 9 * 9
    assert total_open == 2 * (cell_count - 1)
  end

  test "braiding adds extra connections, creating loops" do
    maze = Maze.generate(15, 15, 1.0)

    total_open =
      maze.cells
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()

    cell_count = 15 * 15
    assert total_open > 2 * (cell_count - 1)
  end

  test "door is placed on a reachable cell, away from the entry" do
    maze = Maze.generate(11, 11, 0.3)
    reachable = Maze.distances_from(maze, maze.entry)

    assert Map.has_key?(reachable, maze.door)
    assert reachable[maze.door] > 0
  end

  test "move/3 is blocked by walls and bounded by the grid" do
    maze = Maze.generate(5, 5, 0.0)

    all_dirs = [:north, :south, :east, :west]
    open = Map.fetch!(maze.cells, {0, 0})
    blocked_dirs = Enum.reject(all_dirs, &MapSet.member?(open, &1))

    for dir <- blocked_dirs do
      assert Maze.move(maze, {0, 0}, dir) == :blocked
    end

    for dir <- MapSet.to_list(open) do
      assert {:ok, _} = Maze.move(maze, {0, 0}, dir)
    end
  end

  test "visible_cells/3 only returns cells within the given path-distance radius" do
    maze = Maze.generate(21, 21, 0.3)
    visible = Maze.visible_cells(maze, maze.entry, 3)

    distances = Maze.distances_from(maze, maze.entry)

    assert Enum.all?(visible, fn cell -> Map.get(distances, cell, 999) <= 3 end)
    assert MapSet.member?(visible, maze.entry)
  end
end
