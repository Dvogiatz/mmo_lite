defmodule MmoLite.LootTest do
  use ExUnit.Case, async: true

  alias MmoLite.Loot

  test "generate produces an item with positive damage tied loosely to floor depth" do
    item = Loot.generate(3)

    assert item.damage > 0
    assert item.tier in [:common, :uncommon, :rare, :epic]
    assert is_binary(item.name)
  end

  test "total_damage sums all equipment" do
    items = [%Loot{damage: 3}, %Loot{damage: 5}, %Loot{damage: 2}]
    assert Loot.total_damage(items) == 10
    assert Loot.total_damage([]) == 0
  end
end
