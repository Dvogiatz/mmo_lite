defmodule MmoLite.Leveling do
  @moduledoc """
  Level math per spec §7. Leveling here is formula-driven per kill rather
  than an accumulating XP-threshold curve: every kill grants at least one
  level, plus one more for every full 5 levels the monster is above the
  player. Hearts aren't part of this — they're tied to equipped armor
  (see `MmoLite.Player.max_hearts/1`) and refilled by advancing a floor,
  not by leveling up.
  """

  @doc """
  How many levels a kill against `monster_level` grants a player currently
  at `player_level`: 1, plus 1 more for every full 5-level gap the monster
  is above the player (a monster at or below the player's level still
  grants the base 1). Linear in the gap, so it's self-limiting — no
  separate sanity cap needed.
  """
  def levels_gained(player_level, monster_level) do
    gap = max(monster_level - player_level, 0)
    1 + div(gap, 5)
  end

  @doc "Applies a kill's level reward. Returns `{new_level, levels_gained}`."
  def apply_kill(level, monster_level) do
    gained = levels_gained(level, monster_level)
    {level + gained, gained}
  end
end
