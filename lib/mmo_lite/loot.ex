defmodule MmoLite.Loot do
  @moduledoc """
  Equipment generation (spec §9). Every player has exactly one item per
  slot (`:weapon`, `:armor`, `:boots`); a kill's drop only replaces the
  currently equipped item in its slot if its `value` is strictly higher
  (see `MmoLite.Player.equip/2`) — so power is bounded by the single best
  item found per slot, not by how many kills a player has racked up.

  What `value` means depends on the slot:

    * `:weapon` — flat damage added to attack power, scaling with the
      floor it dropped on (deeper floors drop stronger weapons).
    * `:armor` — bonus to max hearts, floor-independent.
    * `:boots` — bonus to the flee chance on an outmatched combat roll
      (see `MmoLite.Combat.resolve/4`), floor-independent and capped by
      the tier table itself (epic is already the highest useful value).
  """

  defstruct [:id, :slot, :name, :tier, :value]

  @slots [:weapon, :armor, :boots]
  @tier_weights [common: 60, uncommon: 25, rare: 12, epic: 3]

  @weapon_tier_multiplier %{common: 1, uncommon: 2, rare: 3, epic: 5}
  @armor_tier_bonus %{common: 0, uncommon: 1, rare: 2, epic: 3}
  @boots_tier_bonus %{common: 1, uncommon: 2, rare: 3, epic: 4}

  @item_names %{
    weapon: ~w(Blade Axe Hammer Dagger Spear Claw Talisman Gauntlet Shard Fang),
    armor: ~w(Plate Mail Hide Cloak Vest Breastplate Aegis Ward),
    boots: ~w(Boots Greaves Sandals Treads Striders)
  }

  @doc "Generates one piece of loot for a kill on `floor`, for a random slot."
  def generate(floor) do
    slot = Enum.random(@slots)
    tier = roll_tier()

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      slot: slot,
      tier: tier,
      value: value_for(slot, tier, floor),
      name: item_name(slot, tier)
    }
  end

  @doc "The common-tier boots every new player starts already wearing."
  def starter_boots do
    %__MODULE__{
      id: 0,
      slot: :boots,
      tier: :common,
      value: Map.fetch!(@boots_tier_bonus, :common),
      name: "Common Boots"
    }
  end

  @doc "Whether `challenger` is a strict upgrade over `current` (`nil` counts as no item)."
  def better?(nil, %__MODULE__{}), do: true

  def better?(%__MODULE__{value: current}, %__MODULE__{value: challenger}),
    do: challenger > current

  defp value_for(:weapon, tier, floor),
    do: (floor + 1) * Map.fetch!(@weapon_tier_multiplier, tier) + Enum.random(0..2)

  defp value_for(:armor, tier, _floor),
    do: Enum.random(0..2) + Map.fetch!(@armor_tier_bonus, tier)

  defp value_for(:boots, tier, _floor), do: Map.fetch!(@boots_tier_bonus, tier)

  defp item_name(slot, tier),
    do:
      "#{tier |> to_string() |> String.capitalize()} #{Enum.random(Map.fetch!(@item_names, slot))}"

  defp roll_tier do
    total = @tier_weights |> Keyword.values() |> Enum.sum()
    roll = Enum.random(1..total)
    pick_tier(@tier_weights, roll, 0)
  end

  defp pick_tier([{tier, weight} | rest], roll, acc) do
    acc = acc + weight
    if roll <= acc, do: tier, else: pick_tier(rest, roll, acc)
  end
end
