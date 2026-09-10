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
    {:ok, socket: socket}
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

  test "an unknown direction is rejected", %{socket: socket} do
    ref = push(socket, "move", %{"dir" => "sideways"})
    assert_reply ref, :error, %{reason: :invalid_direction}
  end
end
