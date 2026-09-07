defmodule MmoLite.Wire do
  @moduledoc """
  Converts internal `{x, y}` cell tuples into JSON-safe shapes for the
  channel wire format (Jason can't encode tuples, or tuple-keyed maps).
  """

  def cell(nil), do: nil
  def cell({x, y}), do: [x, y]

  @doc "Converts a `%{ {x,y} => open_dirs }` tile map into a JSON-safe list of records."
  def tiles(tiles_map) do
    Enum.map(tiles_map, fn {cell, open} -> %{cell: cell(cell), open: open} end)
  end
end
