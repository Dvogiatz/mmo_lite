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

  test "apply_kill grants +1 heart per level gained, capped at max_hearts" do
    {new_level, new_xp, new_hearts, gained} = Leveling.apply_kill(5, 0, 5, 10)

    assert gained == 2
    assert new_level == 7
    assert new_hearts == 7
    assert new_xp == 10
  end

  test "apply_kill never grants hearts above the configured cap" do
    max_hearts = MmoLite.Config.max_hearts()
    {_level, _xp, new_hearts, _gained} = Leveling.apply_kill(1, 0, max_hearts - 1, 1000)

    assert new_hearts == max_hearts
  end
end
