defmodule MmoLiteWeb.Router do
  use MmoLiteWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {MmoLiteWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  scope "/mmo_lite", MmoLiteWeb do
    pipe_through :browser

    get "/", GameController, :index
  end
end
