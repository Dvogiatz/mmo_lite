defmodule MmoLite.PlayerTest do
  use ExUnit.Case, async: true

  alias MmoLite.{Loot, Player}

  describe "new/2" do
    test "starts with common boots equipped, nothing else, and base hearts" do
      player = Player.new("tok", "Hero")

      assert player.weapon == nil
      assert player.armor == nil
      assert player.boots == Loot.starter_boots()
      assert player.hearts == 5
      assert Player.max_hearts(player) == 5
      assert Player.boots_bonus(player) == 1
    end
  end

  describe "equip/2 for :weapon and :boots" do
    test "equips into an empty slot unconditionally" do
      player = Player.new("tok", "Hero")
      sword = %Loot{slot: :weapon, value: 3, tier: :common, name: "Common Blade"}

      assert %{weapon: ^sword} = Player.equip(player, sword)
    end

    test "keeps the current item when the drop isn't strictly better" do
      player = Player.new("tok", "Hero")
      sword = %Loot{slot: :weapon, value: 3, tier: :common, name: "Common Blade"}
      player = Player.equip(player, sword)

      weaker = %Loot{slot: :weapon, value: 2, tier: :common, name: "Common Dagger"}
      tie = %Loot{slot: :weapon, value: 3, tier: :common, name: "Common Axe"}

      assert Player.equip(player, weaker).weapon == sword
      assert Player.equip(player, tie).weapon == sword
    end

    test "swaps in a strictly better item" do
      player = Player.new("tok", "Hero")
      sword = %Loot{slot: :weapon, value: 3, tier: :common, name: "Common Blade"}
      better = %Loot{slot: :weapon, value: 5, tier: :rare, name: "Rare Axe"}

      player = player |> Player.equip(sword) |> Player.equip(better)
      assert player.weapon == better
    end

    test "boots swap doesn't touch hearts" do
      player = Player.new("tok", "Hero")
      better_boots = %Loot{slot: :boots, value: 3, tier: :rare, name: "Rare Greaves"}

      player = Player.equip(player, better_boots)
      assert player.boots == better_boots
      assert player.hearts == 5
      assert Player.boots_bonus(player) == 3
    end
  end

  describe "equip/2 for :armor" do
    test "equipping the first armor grants hearts equal to its bonus, not a full heal" do
      player = %{Player.new("tok", "Hero") | hearts: 3}
      armor = %Loot{slot: :armor, value: 2, tier: :uncommon, name: "Uncommon Vest"}

      player = Player.equip(player, armor)

      assert player.armor == armor
      assert Player.max_hearts(player) == 7
      # 3/5 -> 5/7: gained exactly the +2 the cap grew by, not healed to full.
      assert player.hearts == 5
    end

    test "swapping to a better armor grants only the cap's increase" do
      player = %{Player.new("tok", "Hero") | hearts: 3}
      first = %Loot{slot: :armor, value: 2, tier: :uncommon, name: "Uncommon Vest"}
      better = %Loot{slot: :armor, value: 5, tier: :epic, name: "Epic Plate"}

      player = player |> Player.equip(first) |> Player.equip(better)

      assert player.armor == better
      assert Player.max_hearts(player) == 10
      # 5/7 -> 8/10: gained exactly the +3 the cap grew by.
      assert player.hearts == 8
    end

    test "a worse or equal armor drop changes nothing, including hearts" do
      player = %{Player.new("tok", "Hero") | hearts: 3}
      armor = %Loot{slot: :armor, value: 2, tier: :uncommon, name: "Uncommon Vest"}
      player = Player.equip(player, armor)

      no_upgrade = %Loot{slot: :armor, value: 2, tier: :uncommon, name: "Uncommon Cloak"}
      player_after = Player.equip(player, no_upgrade)

      assert player_after.armor == armor
      assert player_after.hearts == player.hearts
    end
  end

  describe "power/1" do
    test "is level + weapon damage + active buff, with no weapon counting as 0" do
      player = Player.new("tok", "Hero")
      assert Player.power(player) == 1

      weapon = %Loot{slot: :weapon, value: 4, tier: :common, name: "Common Blade"}
      player = Player.equip(player, weapon)
      assert Player.power(player) == 5

      buffed = %{player | buff: %{expires_at: System.monotonic_time(:millisecond) + 10_000}}
      assert Player.power(buffed) == 5 + MmoLite.Config.killing_spree_damage()
    end
  end

  describe "full_reset/1" do
    test "clears all equipment back to defaults and hearts to the base" do
      weapon = %Loot{slot: :weapon, value: 4, tier: :common, name: "Common Blade"}
      armor = %Loot{slot: :armor, value: 5, tier: :epic, name: "Epic Plate"}

      player =
        Player.new("tok", "Hero")
        |> Player.equip(weapon)
        |> Player.equip(armor)
        |> Map.put(:hearts, 0)

      reset = Player.full_reset(player)

      assert reset.weapon == nil
      assert reset.armor == nil
      assert reset.boots == Loot.starter_boots()
      assert reset.hearts == 5
      assert reset.floor == 0
      assert reset.position == nil
    end
  end
end
