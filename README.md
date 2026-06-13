# MiMo-Code, sandboxed for Apple `container`

Run [MiMo-Code](https://github.com/XiaomiMiMo/MiMo-Code/) — an AI coding agent
that reads/writes code and executes shell commands — inside a hardened sandbox so
**everything it does stays inside the container**, never touching your Mac except
for the one project folder you explicitly hand it.

## Why this is safe

MiMo-Code is an *agent*: it runs commands on its own. The isolation comes in two
layers:

1. **Apple `container` VM isolation.** Apple's
   [`container`](https://github.com/apple/container) runs every container inside
   its **own lightweight Linux VM with a separate kernel**. There is no
   shared-kernel escape path back to macOS — much stronger than Docker's default
   shared-kernel model.
2. **In-container hardening** (this image / `run.sh`):
   - runs as an **unprivileged user** (`mimo`, uid 10001) — no root, no sudo;
   - **minimal package surface** (just TLS roots, `git`, and the MiMo binary);
   - the agent's working directory is **`/workspace`**, the single host folder you
     bind-mount — no other host path is visible inside the VM.

## Prerequisites

- macOS with Apple [`container`](https://github.com/apple/container) installed and
  its system service started (`container system start`).
- (Apple Silicon recommended; the image is arch-native to the VM `container` runs.)

## Build

```sh
container build --tag mimo-code --file Dockerfile .
```

## Run

The `run.sh` helper applies the safe defaults for you:

```sh
./run.sh                    # sandbox the current directory
./run.sh /path/to/project   # sandbox a specific project folder
```

It bind-mounts that one folder to `/workspace` read-write, runs as the `mimo`
user, and removes the container when you exit. The agent can edit **that folder
and nothing else** on your Mac.

Equivalent raw command:

```sh
container run --rm -it --user mimo \
  --volume "$PWD:/workspace" --workdir /workspace \
  mimo-code
```

## Authentication

By default the image bakes in **no secrets**. On first run, MiMo Auto's
zero-config free channel handles auth interactively.

To use your own OpenAI-compatible / MiMo API key instead (still never stored in
the image — passed only at runtime):

```sh
MIMO_API_KEY=sk-xxxx ./run.sh           # forwarded as OPENAI_API_KEY
```

## Persisting the agent's memory

MiMo-Code keeps cross-session memory/config under `~/.mimocode`. With `--rm` that
is wiped each run. To keep it across runs, mount a named volume:

```sh
PERSIST_MEMORY=1 ./run.sh
```

This stores it in a `mimo-memory` volume that lives only inside `container`'s
managed storage — not on your host filesystem tree.

## Network

Outbound HTTPS is allowed so the agent can reach its LLM API; VM isolation still
prevents any access back to the host. Apple `container`'s built-in egress
filtering is coarse — if you need to restrict the agent to *only* its API host,
the practical route today is to run an allow-list HTTP(S) proxy on the host and
point the container at it via `HTTPS_PROXY`, or use a custom `container` network.
Treat MiMo Auto's endpoints + your git remotes as the required allow-list.

## Extending for your project's toolchain

This image deliberately ships only `git` + the MiMo binary. If the agent needs to
build/run code in a specific language, add it to the `Dockerfile` (as the `root`
section, before `USER mimo`), e.g.:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
```

Then rebuild. Keep additions minimal — every tool you add is also a tool the
agent can use, so install only what the work requires.

## Alternatives considered (not used)

> We use **Apple `container` + this Dockerfile**. This section documents the road
> not taken, so the choice is on the record.

**Bare persistent Linux VM (Lima / Tart / UTM / Apple `vz`).** Instead of an OCI
image run by `container`, you could provision a long-lived Linux VM and install
MiMo-Code into it directly (`curl -fsSL https://mimo.xiaomi.com/install | bash`),
then `ssh` in to use the agent.

It is worth being precise about virtualization layers: this is **not** fewer
layers. Apple `container` already runs each container as a *single* lightweight
Linux VM and boots it from the image — the Dockerfile/image is that VM's root
filesystem, not a second VM or a nested runtime. So both options are **one VM**.

The real trade-offs versus the chosen path:

| Aspect | Apple `container` + Dockerfile (chosen) | Persistent VM (Lima/Tart) |
|---|---|---|
| Virtualization layers | 1 VM | 1 VM (same) |
| Reproducibility | Declarative; rebuild from scratch anytime | Imperative; a hand-provisioned pet box |
| Per-task isolation | Fresh `--rm` VM every run | One reused VM that accrues state |
| Host exposure | Explicit single `--volume` mount | Shared folders you wire up manually |
| Fit with "everything within it" | Strong — ephemeral, minimal, one mount | Weaker — long-lived box, larger blast radius |

We chose `container` because it gives the same single-VM isolation while staying
ephemeral, reproducible, and minimal — which matches the goal that everything the
agent does stays confined to the container and the one folder you hand it.
