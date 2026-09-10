defmodule MmoLite.Maze do
  @moduledoc """
  Grid-based labyrinth generation.

  Uses a randomized-DFS ("recursive backtracker") pass to carve a perfect
  maze, then a braiding pass that knocks out a percentage of dead ends to
  create loops — this is deliberately *not* a plain recursive-backtracker
  maze, since those are all dead ends and give players no escape routes
  from monsters.

  A cell is `{x, y}`. The maze is represented as a map of cell => the set
  of directions (`:north | :south | :east | :west`) that are open (walkable)
  from that cell — not a doubled wall-grid, since all movement/vision logic
  here is cell-based.
  """

  defstruct [:width, :height, :cells, :entry, :door]

  @directions [:north, :south, :east, :west]

  @doc """
  Generates a new maze of the given size. `braid_percent` (0.0-1.0) is the
  fraction of dead-end cells that get an extra connection carved to create
  a loop.
  """
  def generate(width, height, braid_percent \\ MmoLite.Config.braid_percent()) do
    cells =
      width
      |> carve(height)
      |> braid(width, height, braid_percent)

    entry = {0, 0}
    door = farthest_cell(cells, entry)

    %__MODULE__{width: width, height: height, cells: cells, entry: entry, door: door}
  end

  @doc "Whether `cell` is within the maze bounds."
  def in_bounds?(%__MODULE__{width: w, height: h}, {x, y}) do
    x >= 0 and x < w and y >= 0 and y < h
  end

  @doc "Attempts to move from `cell` in `dir`. Returns `{:ok, new_cell}` or `:blocked`."
  def move(%__MODULE__{cells: cells} = maze, cell, dir) do
    open_dirs = Map.get(cells, cell, MapSet.new())

    if MapSet.member?(open_dirs, dir) do
      dest = step(cell, dir)
      if in_bounds?(maze, dest), do: {:ok, dest}, else: :blocked
    else
      :blocked
    end
  end

  @doc """
  Returns the set of cells reachable from `origin` within `radius` steps,
  walking only through open passages (no seeing through walls) — this is
  both the fog-of-war visibility set and the payload-size limiter, since
  the server only ever sends tile/monster/player data for cells in here.
  """
  def visible_cells(%__MODULE__{cells: cells}, origin, radius) do
    cells |> bfs_distances(origin, radius) |> Map.keys() |> MapSet.new()
  end

  @doc "Tile data (the set of open directions) for the given cells, for sending to a client."
  def tiles(%__MODULE__{cells: cells}, cell_list) do
    for cell <- cell_list, into: %{}, do: {cell, Map.get(cells, cell, MapSet.new())}
  end

  @doc "Picks a random walkable cell, optionally excluding cells matched by `reject?`."
  def random_cell(%__MODULE__{cells: cells}, reject? \\ fn _ -> false end) do
    cells
    |> Map.keys()
    |> Enum.reject(reject?)
    |> case do
      [] -> nil
      candidates -> Enum.random(candidates)
    end
  end

  @doc "The cell in the maze farthest (by path distance) from `origin`."
  def farthest_cell(cells, origin) when is_map(cells) do
    distances = bfs_distances(cells, origin)
    {cell, _dist} = Enum.max_by(distances, fn {_cell, dist} -> dist end)
    cell
  end

  @doc "Path-distance (in cells) from `origin` to every reachable cell."
  def distances_from(%__MODULE__{cells: cells}, origin), do: bfs_distances(cells, origin)

  # -- generation --------------------------------------------------------

  defp carve(width, height) do
    all_cells = for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
    cells = Map.new(all_cells, &{&1, MapSet.new()})
    start = {0, 0}

    do_carve(cells, [start], MapSet.new([start]), width, height)
  end

  defp do_carve(cells, [], _visited, _w, _h), do: cells

  defp do_carve(cells, [current | rest] = stack, visited, w, h) do
    unvisited_neighbors =
      @directions
      |> Enum.map(&{&1, step(current, &1)})
      |> Enum.filter(fn {_dir, cell} ->
        within?(cell, w, h) and not MapSet.member?(visited, cell)
      end)

    case unvisited_neighbors do
      [] ->
        do_carve(cells, rest, visited, w, h)

      candidates ->
        {dir, next} = Enum.random(candidates)

        cells =
          cells
          |> Map.update!(current, &MapSet.put(&1, dir))
          |> Map.update!(next, &MapSet.put(&1, opposite(dir)))

        do_carve(cells, [next | stack], MapSet.put(visited, next), w, h)
    end
  end

  defp braid(cells, width, height, braid_percent) do
    dead_ends =
      cells
      |> Enum.filter(fn {_cell, open} -> MapSet.size(open) == 1 end)
      |> Enum.map(fn {cell, _open} -> cell end)
      |> Enum.shuffle()

    take_count = round(length(dead_ends) * braid_percent)

    dead_ends
    |> Enum.take(take_count)
    |> Enum.reduce(cells, fn cell, acc ->
      braid_cell(acc, cell, width, height)
    end)
  end

  defp braid_cell(cells, cell, width, height) do
    open_dirs = Map.fetch!(cells, cell)

    closed_neighbors =
      @directions
      |> Enum.reject(&MapSet.member?(open_dirs, &1))
      |> Enum.map(&{&1, step(cell, &1)})
      |> Enum.filter(fn {_dir, neighbor} -> within?(neighbor, width, height) end)

    case closed_neighbors do
      [] ->
        cells

      candidates ->
        {dir, neighbor} = Enum.random(candidates)

        cells
        |> Map.update!(cell, &MapSet.put(&1, dir))
        |> Map.update!(neighbor, &MapSet.put(&1, opposite(dir)))
    end
  end

  # -- BFS -----------------------------------------------------------------

  # Stops expanding past `max_dist`. Integers always compare less than atoms,
  # so the default `:infinity` walks the whole maze.
  defp bfs_distances(cells, origin, max_dist \\ :infinity) do
    do_bfs(cells, :queue.in({origin, 0}, :queue.new()), %{origin => 0}, max_dist)
  end

  defp do_bfs(cells, queue, distances, max_dist) do
    case :queue.out(queue) do
      {:empty, _} ->
        distances

      {{:value, {_cell, dist}}, rest_queue} when dist >= max_dist ->
        do_bfs(cells, rest_queue, distances, max_dist)

      {{:value, {cell, dist}}, rest_queue} ->
        open_dirs = Map.get(cells, cell, MapSet.new())

        {queue, distances} =
          Enum.reduce(open_dirs, {rest_queue, distances}, fn dir, {q, d} ->
            neighbor = step(cell, dir)

            if Map.has_key?(d, neighbor) do
              {q, d}
            else
              {:queue.in({neighbor, dist + 1}, q), Map.put(d, neighbor, dist + 1)}
            end
          end)

        do_bfs(cells, queue, distances, max_dist)
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp within?({x, y}, w, h), do: x >= 0 and x < w and y >= 0 and y < h

  defp step({x, y}, :north), do: {x, y - 1}
  defp step({x, y}, :south), do: {x, y + 1}
  defp step({x, y}, :east), do: {x + 1, y}
  defp step({x, y}, :west), do: {x - 1, y}

  defp opposite(:north), do: :south
  defp opposite(:south), do: :north
  defp opposite(:east), do: :west
  defp opposite(:west), do: :east
end
