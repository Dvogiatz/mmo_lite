defmodule MmoLite.LootTest do
  use ExUnit.Case, async: true

  alias MmoLite.Loot

  test "generate produces an item with positive damage tied loosely to floor depth" do
    item = Loot.generate(3)

    assert item.damage > 0
    assert item.tier in [:common, :uncommon, :rare, :epic]
    assert is_binary(item.name)
  end

  test "best/2 keeps the highest-damage items, best first" do
    items = [%Loot{damage: 3}, %Loot{damage: 5}, %Loot{damage: 2}]
    assert Loot.best(items, 2) == [%Loot{damage: 5}, %Loot{damage: 3}]
    assert Loot.best([], 2) == []
  end
end
