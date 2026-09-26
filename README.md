# wrapit

Sandbox AI coding agents using [bubblewrap](https://github.com/containers/bubblewrap). Give the agent exactly the filesystem access it needs — nothing more.

`wrapit claude` runs Claude Code inside a `bwrap` sandbox defined by a per-project `.wrapit` config file. The agent can read and write your project directory, use your git identity and SSH agent, reach the network, and do its job. It cannot touch the rest of your home directory, modify system files, or see unrelated processes.

**Platform:** Linux only (requires `bwrap`). Bash 3.2+.

## Background

This tool was inspired by Patrick McCanna's post [A detailed writeup of Claude Code constrained by Bubblewrap](https://patrickmccanna.net/a-detailed-writeup-of-claude-code-constrained-by-bubblewrap/), which works through the real tradeoffs of sandboxing an AI agent. The core tension he identifies: the agent needs enough access to do its job, but unconstrained access to your home directory (SSH keys, cloud credentials, shell history, other projects) is a big blast radius for mistakes, or worse.

His approach, and wrapit's, isn't about preventing every conceivable attack. It's about removing the casual risk. System binaries are read-only, so the agent can run tools but can't replace them. The project directory is read/write because the agent actually needs to work. SSH authentication goes through the agent socket, so the agent can `git push` without ever seeing a private key. `/tmp` is an isolated tmpfs. Network access is on by default (the agent needs it), but you can turn it off per project.

The remaining risks are worth being straight about: an agent with network access can exfiltrate anything it can read, and full write access to the project directory means it can still delete your work. The sandbox shrinks the surface area. It doesn't eliminate it.

## Install

There is no `curl | bash` one-liner. `install.sh` copies `wrapit`, `lib/` and
`presets/` out of its own directory, so it needs the source tree beside it — and
a tool whose job is to confine an agent is a poor candidate for an install path
that pipes an unread script into a shell.

```bash
git clone https://github.com/skgchp/wrapit.git
cd wrapit
bash install.sh
```

This installs to `~/.local/share/wrapit`, symlinks `~/.local/bin/wrapit`, and
appends a `PATH` block to whichever of `~/.bashrc`, `~/.zshrc` and the fish
config exist — only when `~/.local/bin` is not already on your `PATH`.

If your dotfiles are generated from a template, pass `--no-path`: an appended
block would be lost, silently, on the next regeneration.

```bash
bash install.sh --no-path    # prints the PATH line for you to place yourself
```

## Quick start

```bash
# Create a .wrapit config for your project (interactive, detects installed agents)
cd ~/my-project
wrapit --init

# Or non-interactive with a known preset
wrapit --init --preset claude-code

# Run an agent sandboxed
wrapit claude 
wrapit aider --model gpt-4o

# Preview the bwrap command without executing
wrapit --dry-run claude

# Validate config for dangerous patterns
wrapit --check

# Run sandbox integrity tests (T1-T6)
wrapit --test
```

## .wrapit config

One directive per line. `#` comments and blank lines are ignored.

```ini
# Read-only bind mount (error if path missing)
ro  ~/.gitconfig

# Read/write bind mount
rw  ~/.claude
rw? ~/.claude.json      # optional: skip silently if missing

# Optional mounts
ro? ~/.nvm
ro? ~/.fnm

[network]
enabled = true          # false to isolate network entirely

[sandbox]
ssh_agent       = true  # forward SSH agent socket (never exposes key files)
tmpfs_tmp       = true  # isolated /tmp
unshare_pid     = true
unshare_ipc     = true
unshare_uts     = true
unshare_cgroup  = true
die_with_parent = true

[env]
clear = true                      # start from an empty environment
pass  = TZ ANTHROPIC_API_KEY      # named variables, taken from your shell
file  = ~/.config/wrapit/env      # KEY=VALUE lines, chmod 600 — for secrets
set   = NODE_ENV=development      # a literal value
```

`$PWD` is always mounted read/write. Paths support `~`, `$PWD`, `$XDG_CONFIG_HOME`, and arbitrary `$VAR` expansion.

Built-in presets: `claude-code`, `aider`, `codex-cli`, `opencode`, `gemini-cli`, `qwen-code`, `mistral-vibe`, `pi`, `goose`, `amp`, `generic`.

### Order matters

Directives are applied in order and a later one wins, because that is how
`bwrap` applies mounts. This is how you say "writable, except for this":

```ini
rw  ~/.pi                         # the agent needs this tree
ro? ~/.pi/agent/models.json       # ...but must not repoint its own models
ro? ~/.pi/agent/web-search.json   # ...or widen its own network reach
```

Reversing those lines hands the agent both files: the `rw` mount is applied last
and covers them again. `wrapit --check` warns when a known-sensitive file is left
writable this way.

### The environment

Without an `[env]` section the sandbox inherits your shell's environment in full.
That is convenient, and it is also the one place the tool is not
deny-by-default — `AWS_SECRET_ACCESS_KEY`, `GITHUB_TOKEN` and a `DATABASE_URL`
from a `direnv` you have forgotten you are in all reach the agent.

`clear = true` starts from nothing and hands back only what you name. **Every
preset sets it**, listing that agent's own API keys, so a config from
`wrapit --init` is closed by default. A `.wrapit` you wrote by hand keeps its
existing behaviour until you add the section: the default for `clear` is `false`.

Put secrets in `file` rather than in the config itself — `.wrapit` is often
committed. Names in `pass` that are unset on the host are skipped silently, so
listing a few extras costs nothing.

### Container work

`wrapit --init` looks for `.lando.yml`, `.ddev/config.yaml`, a Compose file, a
`Dockerfile` or a `.devcontainer/` in the project. When it finds one it writes
that tool's mounts, and the Docker socket, as live directives — a project that
needs containers needs them on every run. When it finds none, the whole block is
written commented out, so opting in stays a visible edit. `wrapit --check` flags
the socket either way, and so does `--init` as it writes the file.

Be clear-eyed about what that costs. The socket is host root: one
`POST /containers/create` with `Privileged: true` or `Binds: ["/:/host"]` and the
rest of the config is decoration. It is in the generated file because the work
does not happen without it, not because it is safe. Two things reduce it:

- **Point it at a rootless daemon.** Abusing a rootless socket yields the daemon's
  user, not host root. Replace the socket line with `rw? $XDG_RUNTIME_DIR/docker.sock`
  and add `set = DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock` under `[env]`.
  Running that daemon as a dedicated user that owns nothing of yours reduces it
  further still.
- **Pin the dev environment's own config.** `.lando.yml` and `.ddev/config.yaml`
  live in `$PWD`, which the agent can write, so an edit there turns a legitimate
  `lando start` into "mount anything, run anything". `--init` writes
  `ro? $PWD/.lando.yml` and friends after the `rw $PWD`, where later-wins makes
  them read-only. Comment them out if the agent genuinely needs to edit them.

Endpoint-filtering socket proxies do not help here: they gate by API path, and the
path you have to allow is the one that escapes.

### User-level defaults

`~/.config/wrapit/defaults.wrapit` is merged before every project's `.wrapit`, so
the project file wins on any setting or path it also covers. Keep every binding
there optional (`ro?` / `rw?`): a missing path is an error, and an error in that
file breaks every project on the machine.

## What the sandbox protects

| Protected | How |
|-----------|-----|
| SSH private keys | Agent socket forwarded; key files never mounted |
| Home directory | Not mounted; only explicitly listed paths are visible |
| System binaries | `/usr`, `/lib`, `/bin` mounted read-only |
| Other projects | Not mounted |
| Process list | New PID namespace; agent sees only its own processes |
| Host `/tmp` | Replaced with an isolated tmpfs |
| IPC, hostname, cgroups | Separate IPC, UTS and cgroup namespaces |
| Shell environment | With `[env] clear = true` (all presets), only named variables are passed |

## What it does not protect

- An agent with network access can exfiltrate anything it can read in the sandbox
- The agent has full write access to `$PWD` — it can delete your work
- A sufficiently determined agent could potentially escape; this targets mistakes, not adversaries
- Mounting the Docker socket (for Lando, ddev, or any container work) hands over trivial root on the host and undoes the rest of the config. No preset mounts it, but `wrapit --init` does write it for a project that carries container markers — see [Container work](#container-work) — and `wrapit --check` flags it on every run

## Creating a custom preset

Presets live in the `presets/` directory of the wrapit install. Each `.preset` file has YAML-style frontmatter followed by `.wrapit` directives.

```
---
name: my-agent
binary: my-agent-bin
description: My custom AI agent
---
# ── My agent config ────────────────────────────────────────────────────────────
# Read/write: stores auth tokens and session state.
rw  ~/.my-agent
```

**Frontmatter fields:**

| Field | Required | Description |
|---|---|---|
| `name` | yes | Preset name (must match filename without `.preset`) |
| `binary` | no | Binary name to detect in `$PATH` during `wrapit --init` |
| `description` | yes | Shown in `--help` and `--init` harness detection |

**Section comment convention:** Each group of bindings should have a comment header using the `# ── Title ──` format and a one-line explanation of what is mounted and why.

**Environment:** the common base sets `[env] clear = true`, so name the variables
your agent reads in its own `[env] pass` line. Names unset on the host are skipped
silently.

```ini
[env]
pass  = MY_AGENT_API_KEY MY_AGENT_BASE_URL
```

The common base (sandbox settings, network, the non-secret part of `[env]`, git
identity) is automatically prepended by wrapit — you only need to list your
agent's specific paths and keys.

Because the base is prepended to *every* preset, anything in it is opted out of
rather than into, so nothing belongs there that some agents would not want — in
particular no sandbox-escape path. Optional tooling like the Docker socket is
offered commented-out in the generated project section instead.

**To test your preset:**

```bash
# Write a .wrapit for the current project
wrapit --init --preset my-agent

# Validate the generated config
wrapit --check

# Preview the bwrap command
wrapit --dry-run my-agent-bin
```

**Adding project-specific paths:** The generated `.wrapit` file includes a commented project-specific section at the end. Uncomment and add paths as needed. Common extras:

```ini
rw? ~/.pyenv              # Python version manager
rw? ~/.cargo              # Rust toolchain
rw? ~/go                  # Go workspace
ro  ~/.aws                # AWS credentials (read-only)
```

## Dependencies

- `bash` 3.2+
- `bwrap` (bubblewrap): `apt install bubblewrap` / `dnf install bubblewrap` / `pacman -S bubblewrap`

## Tests

```bash
bats tests/
```
