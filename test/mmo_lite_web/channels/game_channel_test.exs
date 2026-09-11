defmodule MmoLiteWeb.GameChannelTest do
  # Joins the real, shared floor 0 — not async.
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias MmoLite.Config

  @endpoint MmoLiteWeb.Endpoint

  setup do
    {:ok, reply, socket} =
      MmoLiteWeb.UserSocket
      |> socket()
      |> subscribe_and_join(MmoLiteWeb.GameChannel, "game:play", %{"name" => "Tester"})

    on_exit(fn -> MmoLite.Players.delete(reply.token) end)
    {:ok, socket: socket, reply: reply}
  end

  test "joining pushes the floor roster, including yourself", %{reply: reply} do
    assert_push "roster_update", %{players: roster}
    assert Enum.any?(roster, &(&1.id == reply.id and &1.name == "Tester"))
  end

  test "moves arriving faster than the cooldown are rejected", %{socket: socket} do
    ref = push(socket, "move", %{"dir" => "up"})
    assert_reply ref, :ok, %{outcome: _}

    ref = push(socket, "move", %{"dir" => "up"})
    assert_reply ref, :error, %{reason: :too_fast}

    Process.sleep(Config.move_cooldown_ms())
    ref = push(socket, "move", %{"dir" => "up"})
    assert_reply ref, :ok, %{outcome: _}
  end

  test "a plain step doesn't push player stats", %{socket: socket} do
    # No monsters on the (shared) floor 0, so the step can't become a fight.
    [{pid, _}] = Registry.lookup(MmoLite.FloorRegistry, 0)
    :sys.replace_state(pid, &%{&1 | monsters: %{}})

    ref = push(socket, "move", %{"dir" => "up"})
    assert_reply ref, :ok, %{outcome: outcome}
    assert outcome in [:moved, :blocked]
    refute_push "player_update", _
  end

  test "an unknown direction is rejected", %{socket: socket} do
    ref = push(socket, "move", %{"dir" => "sideways"})
    assert_reply ref, :error, %{reason: :invalid_direction}
  end
end
