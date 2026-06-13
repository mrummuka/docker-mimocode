#!/usr/bin/env bash
#
# Launch MiMo-Code sandboxed under Apple `container` with safe defaults.
#
# Apple `container` runs this inside its own lightweight Linux VM (separate
# kernel), and we additionally confine the agent so the ONLY host path it can
# touch is the project directory you point it at.
#
# Usage:
#   ./run.sh                  # sandbox the current directory ($PWD)
#   ./run.sh /path/to/project # sandbox a specific project directory
#
# Optional environment overrides:
#   IMAGE=mimo-code           # image tag to run (default: mimo-code)
#   PERSIST_MEMORY=1          # also mount a named volume for ~/.mimocode so the
#                             # agent's cross-session memory/config survives runs
#   MIMO_API_KEY=sk-...       # pass an API key instead of MiMo Auto zero-config
#                             # (forwarded as OPENAI_API_KEY inside the container)

set -euo pipefail

IMAGE="${IMAGE:-mimo-code}"
PROJECT_DIR="${1:-$PWD}"

# Resolve to an absolute path; refuse to mount something that doesn't exist.
if [ ! -d "$PROJECT_DIR" ]; then
    echo "error: project directory not found: $PROJECT_DIR" >&2
    exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Guard against accidentally exposing your whole home directory or filesystem.
case "$PROJECT_DIR" in
    "$HOME" | / )
        echo "error: refusing to mount '$PROJECT_DIR' (too broad)." >&2
        echo "       Point run.sh at a specific project folder instead." >&2
        exit 1
        ;;
esac

args=(
    run
    --rm                       # discard the container when the session ends
    --interactive --tty        # interactive agent session
    --user mimo                # never run as root inside the container
    --volume "${PROJECT_DIR}:/workspace"
    --workdir /workspace
)

# Optional: persist the agent's cross-session memory/config across runs.
if [ "${PERSIST_MEMORY:-0}" = "1" ]; then
    args+=( --volume "mimo-memory:/home/mimo/.mimocode" )
fi

# Optional: bring your own key instead of MiMo Auto's zero-config channel.
if [ -n "${MIMO_API_KEY:-}" ]; then
    args+=( --env "OPENAI_API_KEY=${MIMO_API_KEY}" )
fi

echo "Sandboxing: ${PROJECT_DIR} -> /workspace  (image: ${IMAGE})"
exec container "${args[@]}" "$IMAGE"
