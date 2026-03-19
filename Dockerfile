# Use official Elixir image with OTP 26 and Elixir 1.15
FROM hexpm/elixir:1.15.7-erlang-26.2.1-debian-bookworm-20231009-slim as base

# Install system dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Rust toolchain for NIFs
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Set environment variables
ENV MIX_ENV=prod
ENV LANG=C.UTF-8

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create app directory
WORKDIR /app

# Builder stage
FROM base as builder

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy config files
COPY config/config.exs config/${MIX_ENV}.exs config/
COPY config/runtime.exs config/
COPY config/billing.exs config/

# Copy source code
COPY priv priv
COPY lib lib
COPY native native
RUN for dir in native/*/; do \
      cd $dir && cargo build --release && cd /app; \
    done
COPY assets assets

# Compile dependencies and NIFs
RUN mix deps.compile

# Compile Rust NIFs
RUN mix rustler.compile

# Build assets
RUN mix assets.setup
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Build the release
RUN mix release

# Runtime stage
FROM debian:bookworm-slim as runtime

# Install runtime dependencies
RUN apt-get update -y && apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create app user
RUN useradd --create-home app
WORKDIR /home/app
USER app

# Copy release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/lang ./

# Create uploads directory
RUN mkdir -p uploads

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Start the application
CMD ["./bin/lang", "start"]
