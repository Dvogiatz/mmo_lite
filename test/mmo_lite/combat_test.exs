defmodule MmoLite.CombatTest do
  use ExUnit.Case, async: true

  alias MmoLite.Combat

  test "player wins outright when strictly more powerful, no roll needed" do
    assert Combat.resolve(10, 5) == {:win, nil}
  end

  test "a tie favors the player: rolls 2-6 win, only a 1 loses" do
    for roll <- 2..6 do
      assert Combat.resolve(5, 5, roll) == {:tie_win, roll}
    end

    assert Combat.resolve(5, 5, 1) == {:loss, 1}
  end

  test "weaker player still wins on a roll of 6 (upset win)" do
    assert Combat.resolve(3, 10, 6) == {:upset_win, 6}
  end

  test "a roll of 5 is a flee, not a loss" do
    assert Combat.resolve(3, 10, 5) == {:flee, 5}
  end

  test "rolls 1-4 are a loss" do
    for roll <- 1..4 do
      assert Combat.resolve(3, 10, roll) == {:loss, roll}
    end
  end

  test "kill?/1 is true only for win outcomes" do
    assert Combat.kill?(:win)
    assert Combat.kill?(:tie_win)
    assert Combat.kill?(:upset_win)
    refute Combat.kill?(:flee)
    refute Combat.kill?(:loss)
  end

  test "power formulas per spec" do
    assert Combat.player_power(5, 3, 2) == 10
    assert Combat.player_power(5, 3) == 8
    assert Combat.monster_power(20, 4) == 24
  end
end
