# wrapit

Sandbox AI coding agents using [bubblewrap](https://github.com/containers/bubblewrap). Give the agent exactly the filesystem access it needs — nothing more.

`wrapit claude` runs Claude Code inside a `bwrap` sandbox defined by a per-project `.wrapit` config file. The agent can read and write your project directory, use your git identity and SSH agent, reach the network, and do its job. It cannot touch the rest of your home directory, modify system files, or see unrelated processes.

**Platform:** Linux only (requires `bwrap`). Bash 3.2+.

## Background

This tool was inspired by Patrick McCanna's post [A detailed writeup of Claude Code constrained by Bubblewrap](https://patrickmccanna.net/a-detailed-writeup-of-claude-code-constrained-by-bubblewrap/), which works through the real tradeoffs of sandboxing an AI agent. The core tension he identifies: the agent needs enough access to do its job, but unconstrained access to your home directory (SSH keys, cloud credentials, shell history, other projects) is a big blast radius for mistakes, or worse.

His approach, and wrapit's, isn't about preventing every conceivable attack. It's about removing the casual risk. System binaries are read-only, so the agent can run tools but can't replace them. The project directory is read/write because the agent actually needs to work. SSH authentication goes through the agent socket, so the agent can `git push` without ever seeing a private key. `/tmp` is an isolated tmpfs. Network access is on by default (the agent needs it), but you can turn it off per project.

The remaining risks are worth being straight about: an agent with network access can exfiltrate anything it can read, and full write access to the project directory means it can still delete your work. The sandbox shrinks the surface area. It doesn't eliminate it.

## Install

```bash
bash install.sh
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
die_with_parent = true
```

`$PWD` is always mounted read/write. Paths support `~`, `$PWD`, `$XDG_CONFIG_HOME`, and arbitrary `$VAR` expansion.

Built-in presets: `claude-code`, `aider`, `codex-cli`, `opencode`, `gemini-cli`, `qwen-code`, `mistral-vibe`, `pi`, `goose`, `amp`, `generic`.

## What the sandbox protects

| Protected | How |
|-----------|-----|
| SSH private keys | Agent socket forwarded; key files never mounted |
| Home directory | Not mounted; only explicitly listed paths are visible |
| System binaries | `/usr`, `/lib`, `/bin` mounted read-only |
| Other projects | Not mounted |
| Process list | New PID namespace; agent sees only its own processes |
| Host `/tmp` | Replaced with an isolated tmpfs |

## What it does not protect

- An agent with network access can exfiltrate anything it can read in the sandbox
- The agent has full write access to `$PWD` — it can delete your work
- A sufficiently determined agent could potentially escape; this targets mistakes, not adversaries

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

The common base (sandbox settings, network, git identity) is automatically prepended by wrapit — you only need to list your agent's specific paths.

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
