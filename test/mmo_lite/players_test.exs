defmodule MmoLite.PlayersTest do
  # Uses the application's real Players singleton.
  use ExUnit.Case, async: false

  alias MmoLite.Players

  test "a player with a live channel is never stale, but becomes stale once it exits" do
    {token, _player} = Players.create("Idler")
    on_exit(fn -> Players.delete(token) end)

    channel = spawn(fn -> receive(do: (:stop -> :ok)) end)
    Players.attach(token, channel)

    # A timeout of -1 makes every disconnected player stale immediately.
    refute stale?(token)

    send(channel, :stop)
    assert eventually(fn -> stale?(token) end)
  end

  defp stale?(token), do: Enum.any?(Players.stale(-1), fn {t, _} -> t == token end)

  defp eventually(fun, attempts \\ 20) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(5) && eventually(fun, attempts - 1)
    end
  end
end
