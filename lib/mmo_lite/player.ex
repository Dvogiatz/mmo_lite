defmodule MmoLite.Player do
  @moduledoc """
  A player's persistent (in-memory) state, keyed by session token.
  """

  alias MmoLite.Config

  defstruct [
    :token,
    :name,
    :floor,
    :position,
    :level,
    :xp,
    :hearts,
    # Only the best few items, for display (see Config.equipment_listed/0) —
    # every item ever looted still counts toward `equipment_damage`.
    :equipment,
    :equipment_damage,
    :buff,
    :last_seen
  ]

  @type t :: %__MODULE__{}

  def new(token, name) do
    %__MODULE__{
      token: token,
      name: name,
      floor: 0,
      # nil means "not placed yet" — MmoLite.Floor assigns a random walkable
      # spawn cell on join, rather than everyone funneling through one fixed
      # corner.
      position: nil,
      level: 1,
      xp: 0,
      hearts: Config.starting_hearts(),
      equipment: [],
      equipment_damage: 0,
      buff: nil,
      last_seen: System.monotonic_time(:millisecond)
    }
  end

  @doc "Total offensive power, including any still-active Killing Spree buff."
  def power(%__MODULE__{} = player) do
    MmoLite.Combat.player_power(player.level, player.equipment_damage, buff_damage(player))
  end

  def buff_damage(%__MODULE__{buff: nil}), do: 0

  def buff_damage(%__MODULE__{buff: %{expires_at: expires_at}}) do
    if System.monotonic_time(:millisecond) < expires_at,
      do: Config.killing_spree_damage(),
      else: 0
  end

  @doc "Resets to a brand-new run on floor 0 with default hearts/equipment — the last-heart death penalty."
  def full_reset(%__MODULE__{} = player) do
    %{
      player
      | floor: 0,
        position: nil,
        hearts: Config.starting_hearts(),
        equipment: [],
        equipment_damage: 0,
        buff: nil
    }
  end

  @doc "Whether the player's Killing Spree buff is currently active."
  def buff_active?(%__MODULE__{} = player), do: buff_damage(player) > 0
end
