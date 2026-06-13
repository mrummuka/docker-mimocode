# syntax=docker/dockerfile:1
#
# MiMo-Code, sandboxed for Apple `container` (https://github.com/apple/container).
#
# Apple `container` already runs every container inside its own lightweight Linux
# VM with a *separate kernel*, so there is no shared-kernel escape surface back to
# macOS. This image adds in-container hardening on top of that:
#   - runs as an unprivileged user (no root, no sudo)
#   - ships a minimal package surface
#   - confines the agent to /workspace (the single dir you bind-mount at runtime)
#
# Build:  container build --tag mimo-code --file Dockerfile .
# Run:    ./run.sh                       (see run.sh / README.md)

FROM debian:bookworm-slim

# Minimal surface. MiMo-Code installs a self-contained prebuilt binary, so no
# Node/Bun runtime is required at runtime. We add only what the agent genuinely
# needs: TLS roots, curl (for the installer), and git (the agent manages repos).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user. Everything below runs as `mimo`; the agent never has root.
# Create the workspace mount point now, while still root, and hand it to `mimo`
# (creating it after the USER switch would fail — `/` is root-owned).
RUN useradd --create-home --shell /bin/bash --uid 10001 mimo \
    && mkdir -p /workspace \
    && chown mimo:mimo /workspace
USER mimo
WORKDIR /home/mimo

# Install MiMo-Code as the unprivileged user. The official installer drops a
# self-contained binary into ~/.mimocode/bin and (with --no-modify-path) leaves
# our shell config alone — we put just that dir on PATH ourselves.
RUN curl -fsSL https://mimo.xiaomi.com/install | bash -s -- --no-modify-path
ENV PATH="/home/mimo/.mimocode/bin:${PATH}"

# Workspace: the ONLY host path the agent should ever see. Bind-mount your
# project here read-write at runtime (run.sh does this for you). The directory
# was created and chowned above, while we still had root.
WORKDIR /workspace

# Interactive coding-agent session. Auth is handled at first run by MiMo Auto's
# zero-config channel; no secrets are baked into the image. To use your own
# OpenAI-compatible/MiMo key instead, pass it at runtime (see README.md).
# (The installer names the executable `mimo`.)
ENTRYPOINT ["mimo"]
