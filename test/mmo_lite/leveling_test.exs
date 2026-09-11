defmodule MmoLite.LevelingTest do
  use ExUnit.Case, async: true

  alias MmoLite.Leveling

  test "a kill grants at least 1 level, even against a much weaker monster" do
    assert Leveling.levels_gained(10, 1) == 1
  end

  test "a monster at or below the player's level still only grants the base 1" do
    assert Leveling.levels_gained(5, 5) == 1
    assert Leveling.levels_gained(5, 9) == 1
  end

  test "one extra level per full 5-level gap the monster is above the player" do
    assert Leveling.levels_gained(5, 10) == 2
    assert Leveling.levels_gained(5, 14) == 2
    assert Leveling.levels_gained(5, 15) == 3
    assert Leveling.levels_gained(5, 25) == 5
  end

  test "levels_gained is not capped — scales linearly with the level gap" do
    assert Leveling.levels_gained(1, 51) == 11
    assert Leveling.levels_gained(1, 1000) == 200
  end

  test "apply_kill returns the new level and how many were gained" do
    assert Leveling.apply_kill(5, 10) == {7, 2}
    assert Leveling.apply_kill(5, 5) == {6, 1}
  end
end
