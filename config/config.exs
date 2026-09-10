# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mmo_lite,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :mmo_lite, MmoLiteWeb.Endpoint,
  url: [host: "localhost"],
  # Static files are served under the nginx path prefix (see Plug.Static in
  # endpoint.ex), so ~p"/assets/..." resolves to /mmo_lite/assets/... — and
  # in prod to the digested, cache-busting file from cache_manifest.json.
  static_url: [path: "/mmo_lite"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MmoLiteWeb.ErrorHTML, json: MmoLiteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MmoLite.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mmo_lite: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
