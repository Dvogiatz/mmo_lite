defmodule MmoLite.Loot do
  @moduledoc """
  Equipment generation (spec §9). Loot only drops from kills, has no
  currency behind it, and its rarity/tier is loosely tied to the floor's
  monster level range so gear stays roughly relevant to where it dropped
  ("munchkin style" — `equipment_damage` is a direct, stacking power stat).
  """

  defstruct [:id, :name, :damage, :tier]

  @tier_weights [common: 60, uncommon: 25, rare: 12, epic: 3]
  @tier_multiplier %{common: 1, uncommon: 2, rare: 3, epic: 5}
  @item_names ~w(Blade Axe Hammer Dagger Spear Claw Talisman Gauntlet Shard Fang)

  @doc "Generates one piece of loot for a kill on `floor`."
  def generate(floor) do
    tier = roll_tier()
    base = floor + 1
    damage = base * Map.fetch!(@tier_multiplier, tier) + Enum.random(0..2)

    %__MODULE__{
      id: System.unique_integer([:positive, :monotonic]),
      name: "#{tier |> to_string() |> String.capitalize()} #{Enum.random(@item_names)}",
      damage: damage,
      tier: tier
    }
  end

  @doc "Sum of `damage` across a list of equipment — the player's total `equipment_damage`."
  def total_damage(equipment) when is_list(equipment) do
    Enum.reduce(equipment, 0, &(&1.damage + &2))
  end

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
