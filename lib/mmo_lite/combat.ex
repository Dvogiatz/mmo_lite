defmodule MmoLite.Combat do
  @moduledoc """
  Pure stat-check combat resolution (spec §5) — not real-time/twitch combat.

  `player_power = level + weapon_damage + active_buffs`
  `monster_power = level + armor`
  """

  @type outcome :: :win | :tie_win | :upset_win | :flee | :loss

  @doc """
  Resolves a single contact between a player and a monster.

  Returns `{outcome, roll}` where `roll` is the 1d6 roll (nil when the
  player simply outpowers the monster and no roll was needed):

    * `player_power > monster_power` — outright `:win`, no roll.
    * `player_power == monster_power` — an evenly-matched fight tips in the
      player's favor: `:tie_win` on a roll of 2-6, `:loss` on a 1.
    * `player_power < monster_power` — the "last hope" roll: a 6 is always
      `:upset_win`, a 1 is always `:loss`; `boots_bonus` (the equipped
      boots' tier bonus, see `MmoLite.Player.boots_bonus/1`) widens the
      `:flee` band upward from there — the top `boots_bonus` rolls below 6
      flee instead of losing. Common boots (bonus 1) reproduce the base
      1-4 loss / 5 flee / 6 win split; boots cap out at epic (bonus 4),
      leaving only a roll of 1 as a guaranteed loss.

  Pass `roll` to force a specific die result (used by tests); omit it to
  roll for real.
  """
  @spec resolve(integer(), integer(), non_neg_integer(), 1..6 | nil) :: {outcome(), 1..6 | nil}
  def resolve(player_power, monster_power, boots_bonus \\ 1, roll \\ nil) do
    cond do
      player_power > monster_power ->
        {:win, nil}

      player_power == monster_power ->
        roll = roll || :rand.uniform(6)
        if roll == 1, do: {:loss, roll}, else: {:tie_win, roll}

      true ->
        roll = roll || :rand.uniform(6)
        loss_ceiling = 5 - boots_bonus

        cond do
          roll == 6 -> {:upset_win, roll}
          roll > loss_ceiling -> {:flee, roll}
          true -> {:loss, roll}
        end
    end
  end

  @doc "Whether this outcome grants a kill's rewards (level + loot)."
  def kill?(outcome), do: outcome in [:win, :tie_win, :upset_win]

  @doc "Total offensive power for a player, per spec §5."
  def player_power(level, weapon_damage, buff_damage \\ 0) do
    level + weapon_damage + buff_damage
  end

  @doc "Total defensive power for a monster, per spec §5."
  def monster_power(level, armor), do: level + armor
end
