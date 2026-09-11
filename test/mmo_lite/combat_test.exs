defmodule MmoLite.CombatTest do
  use ExUnit.Case, async: true

  alias MmoLite.Combat

  test "player wins outright when strictly more powerful, no roll needed" do
    assert Combat.resolve(10, 5) == {:win, nil}
  end

  test "a tie favors the player: rolls 2-6 win, only a 1 loses" do
    for roll <- 2..6 do
      assert Combat.resolve(5, 5, 1, roll) == {:tie_win, roll}
    end

    assert Combat.resolve(5, 5, 1, 1) == {:loss, 1}
  end

  test "weaker player still wins on a roll of 6 (upset win), regardless of boots" do
    assert Combat.resolve(3, 10, 1, 6) == {:upset_win, 6}
    assert Combat.resolve(3, 10, 4, 6) == {:upset_win, 6}
  end

  test "common boots (bonus 1) reproduce the base split: 1-4 loss, 5 flee, 6 win" do
    for roll <- 1..4, do: assert(Combat.resolve(3, 10, 1, roll) == {:loss, roll})
    assert Combat.resolve(3, 10, 1, 5) == {:flee, 5}
  end

  test "boots bonus widens the flee band and narrows the loss band" do
    # uncommon (+2): 1-3 loss, 4-5 flee
    for roll <- 1..3, do: assert(Combat.resolve(3, 10, 2, roll) == {:loss, roll})
    for roll <- 4..5, do: assert(Combat.resolve(3, 10, 2, roll) == {:flee, roll})

    # epic (+4): only a 1 loses, 2-5 all flee
    assert Combat.resolve(3, 10, 4, 1) == {:loss, 1}
    for roll <- 2..5, do: assert(Combat.resolve(3, 10, 4, roll) == {:flee, roll})
  end

  test "boots_bonus and roll both default (common boots, a real roll) when omitted" do
    for _ <- 1..50 do
      assert {outcome, roll} = Combat.resolve(3, 10)
      assert outcome in [:loss, :flee, :upset_win]
      assert roll in 1..6
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
