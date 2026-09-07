defmodule MmoLite.Combat do
  @moduledoc """
  Pure stat-check combat resolution (spec §5) — not real-time/twitch combat.

  `player_power = level + equipment_damage + active_buffs`
  `monster_power = level + armor`
  """

  @type outcome :: :win | :upset_win | :flee | :loss

  @doc """
  Resolves a single contact between a player and a monster.

  Returns `{outcome, roll}` where `roll` is the 1d6 "last hope" roll (nil
  when the player simply outpowers the monster and no roll was needed).

  Pass `roll` to force a specific die result (used by tests); omit it to
  roll for real.
  """
  @spec resolve(integer(), integer(), 1..6 | nil) :: {outcome(), 1..6 | nil}
  def resolve(player_power, monster_power, roll \\ nil) do
    if player_power > monster_power do
      {:win, nil}
    else
      roll = roll || :rand.uniform(6)

      case roll do
        6 -> {:upset_win, roll}
        5 -> {:flee, roll}
        _ -> {:loss, roll}
      end
    end
  end

  @doc "Whether this outcome grants a kill's rewards (XP + loot)."
  def kill?(outcome), do: outcome in [:win, :upset_win]

  @doc "Total offensive power for a player, per spec §5."
  def player_power(level, equipment_damage, buff_damage \\ 0) do
    level + equipment_damage + buff_damage
  end

  @doc "Total defensive power for a monster, per spec §5."
  def monster_power(level, armor), do: level + armor
end
