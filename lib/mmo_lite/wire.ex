defmodule MmoLite.Wire do
  @moduledoc """
  Converts internal `{x, y}` cell tuples into JSON-safe shapes for the
  channel wire format (Jason can't encode tuples, or tuple-keyed maps).
  """

  import Bitwise

  # Open-direction bits for tiles; assets/js/game/canvas.js decodes the same values.
  @dir_bits %{north: 1, east: 2, south: 4, west: 8}

  def cell(nil), do: nil
  def cell({x, y}), do: [x, y]

  @doc """
  Converts a `%{ {x,y} => open_dirs }` tile map into compact `[x, y, open]`
  triples, where `open` ORs together the bit of each open direction.
  """
  def tiles(tiles_map) do
    for {{x, y}, open} <- tiles_map do
      [x, y, Enum.reduce(open, 0, &(Map.fetch!(@dir_bits, &1) ||| &2))]
    end
  end
end
