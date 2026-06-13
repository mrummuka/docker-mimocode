# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A hardened container image + helper script for running
[MiMo-Code](https://github.com/XiaomiMiMo/MiMo-Code/) (Xiaomi's terminal AI
coding *agent*) under [Apple `container`](https://github.com/apple/container) on
macOS. The whole point is **sandboxing**: MiMo-Code executes shell commands and
edits files on its own, so it must stay confined to the container and the single
project folder the user mounts.

There is no application source code here — the deliverable *is* the
Dockerfile/run.sh/README.

## Commands

```sh
container system start                                  # start container's service (once per boot)
container build --tag mimo-code --file Dockerfile .     # build the image
./run.sh [path]                                         # run, sandboxing path (default: $PWD) -> /workspace
```

`run.sh` env toggles: `IMAGE` (tag, default `mimo-code`), `PERSIST_MEMORY=1`
(named volume for `~/.mimocode` so cross-session memory survives `--rm`),
`MIMO_API_KEY` (forwarded as `OPENAI_API_KEY` instead of MiMo Auto zero-config).

There are no tests/linters — verification is `container build` succeeding and the
agent launching interactively.

## Architecture & invariants (don't regress these)

The security model has two layers; changes must preserve both:

1. **Apple `container` VM isolation** — each container is its own lightweight
   Linux VM (separate kernel). This is why the image, not just Docker conventions,
   is the right unit. Do not assume Docker daemon / shared-kernel semantics.
2. **In-container hardening** in the `Dockerfile`:
   - Runs as unprivileged user `mimo` (uid 10001), no root/sudo.
   - Minimal package surface (`ca-certificates`, `curl`, `git` only).
   - `/workspace` is the sole host-facing path (a runtime bind mount).
   - **No secrets baked into the image** — auth happens at runtime.

Dockerfile ordering matters: anything needing root (apt, `useradd`, creating &
`chown`ing `/workspace`) must happen **before** the `USER mimo` switch. MiMo-Code
is installed via the official installer as `mimo`; the executable is named
**`mimo`** and lands in `~/.mimocode/bin` (which is added to `PATH`).
`ENTRYPOINT` is `mimo`.

`run.sh` enforces the safe defaults (`--rm`, `-it`, `--user mimo`, single
`/workspace` mount) and refuses to mount `$HOME` or `/`. Keep that guard.

When adding language toolchains for a project, add them to the root section of the
Dockerfile (before `USER mimo`) and keep additions minimal — every installed tool
is also a tool the agent can run.
