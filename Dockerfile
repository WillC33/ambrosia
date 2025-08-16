# Build stage
FROM elixir:1.15-alpine AS builder

RUN apk add --no-cache gcc g++ make libc-dev openssl-dev git
ENV MIX_ENV=prod
WORKDIR /app

# Create non-root build user
RUN adduser -D builder && chown builder:builder /app
USER builder

COPY --chown=builder mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

COPY --chown=builder config ./config
COPY --chown=builder lib ./lib
RUN mix compile && mix release

# Runtime stage - use same Alpine as Elixir image
FROM alpine:3.18

# Install runtime deps 
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc \
    && apk upgrade --no-cache \
    && rm -rf /var/cache/apk/*

# Create non-root user with specific UID
RUN addgroup -g 1000 -S ambrosia && \
    adduser -u 1000 -S -G ambrosia -h /app -s /bin/false ambrosia

WORKDIR /app

# Create necessary directories with proper permissions
RUN mkdir -p /app/gemini /app/gemini-sample && \
    chown -R ambrosia:ambrosia /app && \
    chmod 755 /app

# Copy release and scripts as non-root
COPY --from=builder --chown=ambrosia:ambrosia /app/_build/prod/rel/ambrosia ./
COPY --chown=ambrosia:ambrosia start.sh ./
COPY --chown=ambrosia:ambrosia gemini-sample /app/gemini-sample

RUN chmod +x start.sh

# Drop privileges
USER ambrosia

# Only expose Gemini port
EXPOSE 1965

# Use exec form to prevent shell injection
ENTRYPOINT ["./start.sh"]
