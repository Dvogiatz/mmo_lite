defmodule MmoLiteWeb.GameControllerTest do
  use MmoLiteWeb.ConnCase

  test "GET /mmo_lite/", %{conn: conn} do
    conn = get(conn, ~p"/mmo_lite/")
    assert html_response(conn, 200) =~ "game-canvas"
  end
end
