defmodule MmoLite.Reaper do
  @moduledoc """
  Periodically removes players who haven't been seen in a while (spec §1:
  "reaps inactive players after a timeout"). A reaped token simply
  disappears from `MmoLite.Players` — a later reconnect with that token
  won't be found and is treated as a brand-new player, per spec.
  """

  use GenServer

  alias MmoLite.{Config, Floor, Players}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @impl true
  def init(:ok) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Config.reap_timeout_ms()
    |> Players.stale()
    |> Enum.each(fn {token, player} ->
      # The player's channel normally already called Floor.leave on
      # disconnect; only bother if that floor process still happens to be
      # running (a stale token isn't necessarily still registered there).
      case Registry.lookup(MmoLite.FloorRegistry, player.floor) do
        [{_pid, _}] -> Floor.leave(player.floor, token)
        [] -> :ok
      end

      Players.delete(token)
    end)

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, Config.reap_interval_ms())
end
