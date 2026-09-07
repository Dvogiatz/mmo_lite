defmodule MmoLiteWeb.Router do
  use MmoLiteWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {MmoLiteWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end
end
