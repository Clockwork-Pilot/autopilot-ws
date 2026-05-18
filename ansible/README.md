# GitHub Actions Self-Hosted Runner

Ansible playbook to install a GitHub Actions self-hosted runner on your local machine, targeting any GitHub repo you own. The runner is registered at the repo level and runs as a systemd user service.

## Prerequisites

- Python deps: `pip install ansible yq`
- System deps: Docker (used by workflows) and `jq` (required by `yq` to parse issue frontmatter) — e.g. `sudo apt install docker.io jq`

## Usage

Install a self-hosted runner for any GitHub repo you own. Replace `<github-username>` with your GitHub login and `<your-repo>` with the target repo name.

### Setup

1. Get a registration token:
   ```
   https://github.com/<github-username>/<your-repo>/settings/actions/runners/new
   ```
   Copy the token from the `--token ...` line.

2. Install the runner:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini runner-install.yml \
       -e runner_token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
       -e runner_repo=<github-username>/<your-repo> \
       -e runner_github_username=<github-username> \
       -e docker_files=/abs/path/to/autopilot-ws/docker-files
   ```

   All four `-e` vars are required; the playbook will abort if any is missing.

3. (Optional) Add gVisor sandboxing:
   ```bash
   ansible-playbook -i inventory.ini gvisor-install.yml --ask-become-pass
   ```

### Playbooks

- **`runner-install.yml`** — Install GitHub Actions self-hosted runner
- **`gvisor-install.yml`** — Add gVisor/runsc sandboxing (requires `--ask-become-pass`)

## Configuration

Override any of these via `-e` or by editing `vars.yml`:

| Variable | Default | Description |
|---|---|---|
| `runner_repo` | **required** | GitHub repo the runner is registered to, e.g. `<github-username>/<your-repo>` |
| `runner_token` | **required** | One-shot registration token from the GitHub runner setup page |
| `docker_files` | **required** | Absolute host path for persistent dirs (cargo, claude credentials) mounted into the coding-agent container |
| `runner_github_username` | `git config user.username` | Must match the runner label that `issue-trigger.yml` checks for |
| `runner_name` | hostname | Runner name shown in GitHub UI |
| `runner_labels` | `coding-agent,<username>` | Labels used in `runs-on` |
| `runner_install_dir` | `~/.local/share/github-runner` | Install path |
| `runner_version` | `2.333.1` | Runner binary version |
| `claude_extra_docker_args` | `""` | Extra `docker run` args, e.g. `"-v /mydata:/mydata"` |

## Service management

Replace `<user>.<repo>` with your runner's `{runner_repo | replace('/', '.')}`:

```bash
# Status
systemctl --user status 'actions.runner.<user>.<repo>.*'

# Stop / start
systemctl --user stop   'actions.runner.<user>.<repo>.*'
systemctl --user start  'actions.runner.<user>.<repo>.*'

# Logs
journalctl --user -u 'actions.runner.<user>.<repo>.*' -f
```

## gVisor Sandboxing (Optional)

Add gVisor's `runsc` container runtime to sandbox untrusted PR code:

```bash
ansible-playbook -i inventory.ini gvisor-install.yml
```

### What it does

- Downloads gVisor's `runsc` runtime binary
- Registers `runsc` as an available Docker runtime (`/usr/local/bin/runsc`)
- Enables `live-restore` in Docker daemon config (running containers survive daemon restarts)
- Updates Docker daemon to recognize the `runsc` runtime
- Sets `DOCKER_RUNTIME=--runtime=runsc` environment variable for the runner

> **Warning:** The playbook will prompt for confirmation before restarting the Docker daemon. A restart is required — it cannot be avoided. If `live-restore` was already enabled in your Docker config, running containers will survive. Otherwise **all running containers will be stopped**.

Containers then execute with `docker run --runtime=runsc`, providing kernel-level sandboxing instead of direct host kernel access.

### Configuration

Override gVisor settings in `vars.yml` or via `-e`:

| Variable | Default | Description |
|---|---|---|
| `runsc_arch` | auto-detected | System architecture (x86_64 or aarch64) |
| `runsc_download_url` | `https://storage.googleapis.com/gvisor/releases/release/latest/runsc` | gVisor runsc binary download URL |

## Playbook Structure

```
ansible/
├── runner-install.yml          # Install GitHub Actions runner
├── gvisor-install.yml          # Install gVisor/runsc sandboxing
├── vars.yml                    # Shared variables (runner config, gVisor defaults)
├── inventory.ini               # Ansible inventory (localhost by default)
├── roles/gvisor/               # gVisor role
│   ├── tasks/main.yml          # Install runsc, configure Docker
│   ├── defaults/main.yml       # gVisor version, architecture, URLs
│   └── templates/              # Configuration templates
│       └── runsc-runtime.json.j2
└── README.md
```

## Using the runner in a workflow

```yaml
jobs:
  my-job:
    runs-on: [self-hosted, coding-agent]
```

To use gVisor sandboxing, workflows run automatically with `--runtime=runsc` (set by Ansible).
