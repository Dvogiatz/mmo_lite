defmodule MmoLite.LevelingTest do
  use ExUnit.Case, async: true

  alias MmoLite.Leveling

  test "a kill grants at least 1 level, even against a much weaker monster" do
    assert Leveling.levels_gained(10, 1) == 1
  end

  test "levels_gained scales when the monster heavily outlevels the player" do
    assert Leveling.levels_gained(5, 10) == 2
    assert Leveling.levels_gained(5, 25) == 5
  end

  test "levels_gained is capped at the configured sanity limit" do
    cap = MmoLite.Config.max_levels_per_kill()
    assert Leveling.levels_gained(1, 1000) == cap
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
