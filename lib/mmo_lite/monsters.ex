defmodule MmoLite.Monsters do
  @moduledoc """
  Monster stat generation and respawn-location selection (spec §6).
  """

  alias MmoLite.{Config, Maze}

  defstruct [:id, :level, :armor, :position]

  @doc "Level for a monster on `floor`: `floor*10 + random(1,10)`."
  def level_for_floor(floor), do: floor * 10 + Enum.random(1..10)

  @doc "Armor for a monster on `floor` — scales loosely with floor depth."
  def armor_for_floor(floor), do: Enum.random(0..(floor + Config.monster_armor_max_bonus()))

  @doc "Generates one monster at `position` for `floor`."
  def generate(floor, position) do
    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      level: level_for_floor(floor),
      armor: armor_for_floor(floor),
      position: position
    }
  end

  @doc "Generates a floor's fixed-size starting monster pool."
  def generate_pool(floor, %Maze{} = maze, count \\ Config.monster_pool_size()) do
    for _ <- 1..count do
      position = Maze.random_cell(maze, &(&1 == maze.entry))
      generate(floor, position)
    end
  end

  @doc """
  Picks a respawn location for a new monster: a random walkable cell
  outside every current player's vision radius (retried a few times),
  falling back to the cell farthest (by minimum distance) from all
  players if every attempt lands within someone's sight.
  """
  def respawn_location(maze, player_positions, attempts \\ 10)

  def respawn_location(%Maze{} = maze, [], _attempts),
    do: Maze.random_cell(maze, &(&1 == maze.entry))

  def respawn_location(%Maze{} = maze, player_positions, attempts) do
    radius = Config.vision_radius()
    visible_sets = Enum.map(player_positions, &Maze.visible_cells(maze, &1, radius))

    found =
      Stream.repeatedly(fn -> Maze.random_cell(maze, &(&1 == maze.entry)) end)
      |> Stream.take(attempts)
      |> Enum.find(fn cell -> not Enum.any?(visible_sets, &MapSet.member?(&1, cell)) end)

    found || farthest_from_players(maze, player_positions)
  end

  defp farthest_from_players(%Maze{} = maze, player_positions) do
    distance_maps = Enum.map(player_positions, &Maze.distances_from(maze, &1))

    maze.cells
    |> Map.keys()
    |> Enum.max_by(fn cell ->
      distance_maps
      |> Enum.map(&Map.get(&1, cell, 0))
      |> Enum.min()
    end)
  end
end
