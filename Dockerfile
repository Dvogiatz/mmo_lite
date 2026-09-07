# ---- Build stage ----
FROM hexpm/elixir:1.18.2-erlang-27.3.4.12-ubuntu-noble-20260509.1 AS build

WORKDIR /app

ENV MIX_ENV=prod

# Install build tools
RUN apt-get update -y && \
    apt-get install -y build-essential git nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Fetch deps
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy config before compiling deps (needed for compile-time config)
COPY config config/
RUN mix deps.compile

# Compile app (needed before assets — phoenix-colocated resolves from _build)
COPY lib lib/
RUN mix compile

# Build assets
COPY assets assets/
COPY priv priv/
RUN mix assets.deploy

# Build release
RUN mix release

# ---- Runtime stage ----
FROM ubuntu:noble AS runtime

WORKDIR /app

ENV PHX_SERVER=true \
    MIX_ENV=prod

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN useradd --create-home app
USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/mmo_lite ./

EXPOSE 4000

CMD ["bin/mmo_lite", "start"]
