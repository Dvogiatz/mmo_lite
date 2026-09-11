defmodule MmoLite.Config do
  @moduledoc """
  Tunable numeric constants for the game. The spec leaves several of these
  as explicitly open/TBD (heart cap, loot tiers, door level requirements) —
  they live here, in one place, so they're easy to retune without touching
  game logic.
  """

  @maze_width 21
  @maze_height 21
  # Higher than a "classic" maze's ~10-20% — knocks out most dead ends so
  # the floor plays more like an open layout with loops (players need an
  # escape route around a monster, not just one dead-end corridor into it).
  @braid_percent 0.6

  # Also the floor for max_hearts (see MmoLite.Player.max_hearts/1) — armor
  # is the only thing that raises the cap above this.
  @starting_hearts 5

  @vision_radius 6

  # Minimum gap between accepted moves on one channel (20 moves/s). The
  # client already waits for each reply, so this only bites clients pushing
  # raw socket messages — each move triggers a broadcast to the whole floor.
  @move_cooldown_ms 50

  @monster_pool_size 14
  @monster_respawn_ms 15_000
  @monster_armor_max_bonus 5

  @reap_interval_ms 60_000
  @reap_timeout_ms 5 * 60_000

  @floor_idle_teardown_ms 30_000

  @killing_spree_damage 5
  @killing_spree_duration_ms 6_000

  def maze_width, do: @maze_width
  def maze_height, do: @maze_height
  def braid_percent, do: @braid_percent

  def starting_hearts, do: @starting_hearts

  def vision_radius, do: @vision_radius

  def move_cooldown_ms, do: @move_cooldown_ms

  def monster_pool_size, do: @monster_pool_size
  def monster_respawn_ms, do: @monster_respawn_ms
  def monster_armor_max_bonus, do: @monster_armor_max_bonus

  def reap_interval_ms, do: @reap_interval_ms
  def reap_timeout_ms, do: @reap_timeout_ms

  def floor_idle_teardown_ms, do: @floor_idle_teardown_ms

  def killing_spree_damage, do: @killing_spree_damage
  def killing_spree_duration_ms, do: @killing_spree_duration_ms

  @doc """
  Minimum player level required to use floor `n`'s door, roughly tracking
  that floor's monster level range (`n*10+1 .. n*10+10`).
  """
  def door_level_requirement(floor), do: floor * 10 + 5
end
