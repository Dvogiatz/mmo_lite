defmodule MmoLite.Player do
  @moduledoc """
  A player's persistent (in-memory) state, keyed by session token.
  """

  alias MmoLite.{Config, Loot}

  defstruct [
    :token,
    :name,
    :floor,
    :position,
    :level,
    :hearts,
    # One item per slot, kept only if it's a strict upgrade over what's
    # already equipped (see `equip/2`) — `:weapon` and `:armor` start
    # empty, `:boots` starts with the common-tier starter pair.
    :weapon,
    :armor,
    :boots,
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
      hearts: Config.starting_hearts(),
      weapon: nil,
      armor: nil,
      boots: Loot.starter_boots(),
      buff: nil,
      last_seen: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Equips `item` into its slot if it's a strict upgrade over what's there,
  otherwise returns `player` unchanged.

  Armor is the one slot with a side effect: since it raises `max_hearts/1`,
  swapping in a better one grants hearts equal to exactly the cap increase
  (not a full heal) — someone at 3/5 who finds a +2 armor ends up at 5/7,
  still missing the same 2 hearts they were before.
  """
  def equip(%__MODULE__{} = player, %Loot{slot: :weapon} = item) do
    if Loot.better?(player.weapon, item), do: %{player | weapon: item}, else: player
  end

  def equip(%__MODULE__{} = player, %Loot{slot: :boots} = item) do
    if Loot.better?(player.boots, item), do: %{player | boots: item}, else: player
  end

  def equip(%__MODULE__{} = player, %Loot{slot: :armor} = item) do
    if Loot.better?(player.armor, item) do
      gained = item.value - armor_bonus(player.armor)
      %{player | armor: item, hearts: player.hearts + gained}
    else
      player
    end
  end

  @doc "Total offensive power, including any still-active Killing Spree buff."
  def power(%__MODULE__{} = player) do
    MmoLite.Combat.player_power(player.level, weapon_damage(player), buff_damage(player))
  end

  @doc "Current max hearts: a base of `Config.starting_hearts/0` plus the equipped armor's bonus."
  def max_hearts(%__MODULE__{armor: armor}), do: Config.starting_hearts() + armor_bonus(armor)

  @doc "The equipped boots' bonus to the flee chance on an outmatched combat roll."
  def boots_bonus(%__MODULE__{boots: %Loot{value: value}}), do: value

  defp weapon_damage(%__MODULE__{weapon: nil}), do: 0
  defp weapon_damage(%__MODULE__{weapon: %Loot{value: value}}), do: value

  defp armor_bonus(nil), do: 0
  defp armor_bonus(%Loot{value: value}), do: value

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
        weapon: nil,
        armor: nil,
        boots: Loot.starter_boots(),
        buff: nil
    }
  end

  @doc "Whether the player's Killing Spree buff is currently active."
  def buff_active?(%__MODULE__{} = player), do: buff_damage(player) > 0
end
