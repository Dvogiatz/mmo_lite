defmodule MmoLiteWeb.GameController do
  use MmoLiteWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
