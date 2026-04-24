# Get
``` bash
# separately clone repo
git clone git@github.com:Clockwork-Pilot/autopilot-ws.git

# fetch / update submodules: ra_ap_shell, claude-plugin
git submodule update --init --recursive
```

# Build Docker:

```bash
docker build -t autopilot-ws .
```

## Layering a user image on top of the base

A user Dockerfile (e.g. `autopilot-selftest/Dockerfile.agent-sample`) adds extra tooling on top of the workspace base. **The same file is used in both contexts:**

- **CI** (`autopilot`'s `ensure-docker-image` action) — `docker build` runs with no build-args; `FROM ${BASE_IMAGE}` falls back to the Dockerfile's `ARG BASE_IMAGE` default, which points at the published registry image `ghcr.io/clockwork-pilot/autopilot-ws:latest`.
- **Local dev** (this repo's `build-docker-workspace.sh`) — you want the freshly built **local** base, not the stale image from the registry. The script passes `--build-arg BASE_IMAGE=autopilot-ws-base`, which overrides the default and resolves `FROM ${BASE_IMAGE}` to the locally built tag. No registry pull, no `docker tag` dance.

The Dockerfile only needs one contract to support both:

```dockerfile
ARG BASE_IMAGE=ghcr.io/clockwork-pilot/autopilot-ws:latest
FROM ${BASE_IMAGE}
```

Example: build an agent image from the sample Dockerfile in the sibling `autopilot-selftest` repo:

```bash
# Sibling checkout layout:
#   clockwork-pilot/
#     autopilot-ws/           ← you are here
#     autopilot-selftest/
#       Dockerfile.agent-sample

./build-docker-workspace.sh ../autopilot-selftest/Dockerfile.agent-sample
```

What the script does:
1. `docker build -f Dockerfile -t autopilot-ws-base .` — builds the base image from this repo.
2. `docker build -f ../autopilot-selftest/Dockerfile.agent-sample -t autopilot-ws --build-arg BASE_IMAGE=autopilot-ws-base .` — builds the layered image, redirecting `FROM ${BASE_IMAGE}` to the fresh local base.

The resulting `autopilot-ws` tag is what `run-docker-workspace.sh` runs. CI workflows reference the exact same Dockerfile and get the registry-pulled base automatically.

# Run in docker

`run-docker-workspace.sh` mounts the host repo at `/workspace` inside the container. You must export `PROJECT_ROOT` (absolute host path); the script exits with an error if it's unset.

## Docker artifacts folder

The `docker-files/` directory is automatically created when running the Docker image via `run-docker-workspace.sh`. This folder contains persistent artifacts from the container:

- `.cargo/` — Rust package manager cache and registry data
- `.credentials/` — Claude Code credentials, plugins, and authentication tokens
- `.local/` — Local user data and configuration
- `.claude.local.json` — Local Claude Code settings and session state
- `venv/` — Python virtual environment with installed packages

These artifacts persist between container runs, eliminating the need to re-download packages and re-authenticate on subsequent executions. This folder should typically be added to `.gitignore` as it contains machine-specific state and credentials.

```bash
export PROJECT_ROOT=/abs/path/to/repo

# install claude code
./run-docker-workspace.sh "curl -fsSL https://claude.ai/install.sh | bash"

# run claude code using defaults
./run-docker-workspace.sh

# or run command explicitly. Note: destination mounted paths are already set.
./run-docker-workspace.sh claude --dangerously-skip-permissions --model claude-opus-4-6 --plugin-dir /plugin

# run bash
./run-docker-workspace.sh bash

# test
./run-docker-workspace.sh make c-tcl-tests
```

# Notes on using dev loop

## Load y2 plugin and re-render spec
Our dev loop highly depends on validating features' constraints of our `spec.k.json`.
Since we don't have any tools for making changes in verified constrains, and agent is prohibited from making changes
in constraints that once failed. Sometimes we need to make changes in constraints, so we use hacky way - actually
manually edit spec file just in text editor. So usually after this it looses its read-only attrs which needs to be restored.
We just instruct agent to `load y2 plugin and re-render spec` and it restores read-only attrs.

# Issue-driven coding agent (self-hosted runner)

Moved to the [autopilot](../autopilot/README.md) repo, which hosts the GitHub Actions workflows, composite actions, and ansible playbook for the self-hosted runner. This repo (the workspace image) is what `autopilot` invokes inside Docker.

# Restricting claude code agent

For some reason we didn't see permissions work when we specify `--dangerously-skip-permissions` flag, so we use own permissions tricks.

See `docker-scripts/proxy_wrapper.py` approach and related 
config `docker-scripts/proxy_wrapper_config.json`

## Standard Claude code permissions model _won't_ _work_ for us

When used in combination with `--dangerously-skip-permissions` flag, it wasn't working as expected.
So this part is just a memory.
It is corresponding to `~/.claude/settings.json` inside docker container.
Set permisisons manually in file:
`docker-claude-artifacts-c2rust-patterns/.credentials/settings.json`: 

```json
{
  "permissions": {
    "deny": [
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git config:*)",
      "Bash(git log:*)",
      "Bash(gh:*)",
      "Agent(Explore)",
      "Write(/workspace/*)",
      "Edit(/workspace/*)"
    ]
  }
}
```
