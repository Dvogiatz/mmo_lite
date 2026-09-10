defmodule MmoLiteWeb.GameControllerTest do
  use MmoLiteWeb.ConnCase

  test "GET /mmo_lite/", %{conn: conn} do
    conn = get(conn, ~p"/mmo_lite/")
    assert html_response(conn, 200) =~ "game-canvas"
  end

  test "assets are linked under the /mmo_lite prefix", %{conn: conn} do
    html = conn |> get(~p"/mmo_lite/") |> html_response(200)

    assert html =~ ~s(src="/mmo_lite/assets/js/app.js)
    assert html =~ ~s(href="/mmo_lite/assets/css/app.css)
  end
end
