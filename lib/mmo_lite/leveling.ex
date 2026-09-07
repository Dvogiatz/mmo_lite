defmodule MmoLite.Leveling do
  @moduledoc """
  XP/leveling math per spec §7. Leveling here is formula-driven per kill
  rather than an accumulating XP-threshold curve: every kill grants at
  least one level, scaled up when the monster heavily outlevels the
  player. `xp` is tracked as a cumulative display counter alongside it.
  """

  alias MmoLite.Config

  @doc """
  How many levels a kill against `monster_level` grants a player currently
  at `player_level`, per spec: `max(1, floor(monster_level / player_level))`,
  capped at `Config.max_levels_per_kill/0` as a sanity limit.
  """
  def levels_gained(player_level, monster_level) do
    raw = max(1, div(monster_level, player_level))
    min(raw, Config.max_levels_per_kill())
  end

  @doc "Display XP awarded for a kill (a flavor counter, not a level threshold)."
  def xp_gained(monster_level), do: monster_level

  @doc """
  Applies a kill's rewards to level/xp/hearts. Each level gained grants
  +1 heart (capped at `Config.max_hearts/0`).

  Returns `{new_level, new_xp, new_hearts, levels_gained}`.
  """
  def apply_kill(level, xp, hearts, monster_level) do
    gained = levels_gained(level, monster_level)
    new_level = level + gained
    new_xp = xp + xp_gained(monster_level)
    new_hearts = min(hearts + gained, Config.max_hearts())

    {new_level, new_xp, new_hearts, gained}
  end
end
