defmodule MmoLite.LootTest do
  use ExUnit.Case, async: true

  alias MmoLite.Loot

  test "generate produces an item in one of the three slots with a positive value" do
    item = Loot.generate(3)

    assert item.slot in [:weapon, :armor, :boots]
    assert item.value > 0
    assert item.tier in [:common, :uncommon, :rare, :epic]
    assert is_binary(item.name)
  end

  test "starter_boots is a common-tier boots item" do
    boots = Loot.starter_boots()

    assert boots.slot == :boots
    assert boots.tier == :common
    assert boots.value == 1
  end

  test "better?/2 treats no current item as always beatable" do
    assert Loot.better?(nil, %Loot{value: 0})
  end

  test "better?/2 requires a strictly higher value to count as an upgrade" do
    assert Loot.better?(%Loot{value: 3}, %Loot{value: 5})
    refute Loot.better?(%Loot{value: 5}, %Loot{value: 5})
    refute Loot.better?(%Loot{value: 5}, %Loot{value: 3})
  end
end
