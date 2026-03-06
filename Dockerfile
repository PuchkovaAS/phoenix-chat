cat > Dockerfile << 'EOF'
# Build stage
FROM elixir:1.19-alpine AS build

RUN apk add -c build git nodejs npm

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY assets assets
RUN cd assets && npm install && npm run deploy

COPY config config
COPY lib lib
COPY priv priv

RUN mix do compile, phx.digest

# Release stage
FROM alpine:3.19 AS app

RUN apk add -c openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel ./

ENV ECTO_IPV6=true
ENV ERL_AFLAGS="-proto_dist inet6_tcp"

EXPOSE 4000

CMD ["/app/bin/server", "start"]
EOF

# Закоммитьте и запушьте
git add Dockerfile
git commit -m "Add Dockerfile"
git push origin master
