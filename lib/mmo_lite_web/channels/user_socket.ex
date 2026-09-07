defmodule MmoLiteWeb.UserSocket do
  use Phoenix.Socket

  channel "game:play", MmoLiteWeb.GameChannel

  # No accounts/login — auth is deferred entirely to the channel join,
  # which accepts either a known session token (rehydrate) or a name
  # (brand-new player). See MmoLiteWeb.GameChannel.
  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
