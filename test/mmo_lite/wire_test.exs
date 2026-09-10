defmodule MmoLite.WireTest do
  use ExUnit.Case, async: true

  alias MmoLite.Wire

  test "tiles/1 encodes open directions as a bitmask (N=1, E=2, S=4, W=8)" do
    tiles = %{{1, 2} => MapSet.new([:north, :west]), {3, 4} => MapSet.new([:east, :south])}
    assert Enum.sort(Wire.tiles(tiles)) == [[1, 2, 9], [3, 4, 6]]
  end
end
