# wrapit — Specification

**Version:** 0.1 (draft)
**Target:** Claude Code implementation
**Platform:** Linux only (bubblewrap / `bwrap`)

---

## Overview

`wrapit` is a CLI tool that sandboxes AI agent harnesses (Claude Code, Aider, Gemini CLI, etc.) using [bubblewrap](https://github.com/containers/bubblewrap). It reads a per-project `.wrapit` config file to determine which paths the agent can access and with what permissions, then constructs and executes the appropriate `bwrap` command.

The goal is to give agents the minimum filesystem access they need to do useful work, while keeping the rest of the host system invisible and unmodifiable.

---

## Core Design Principles

1. **Minimal by default.** System binaries are always mounted read-only. Everything else must be explicitly opted in via `.wrapit`. This holds for the environment as well as the filesystem — see [`[env]`](#sections).
2. **Order is significant.** `bwrap` applies mount operations in the order given and `wrapit` preserves config order, so a later directive wins over an earlier one covering the same path. That is what lets a subtree be mounted `rw` with a single file pinned `ro` inside it.
3. **Per-project config.** `.wrapit` lives in the project directory, committed to version control. The sandbox reflects the project's needs.
4. **Global user defaults.** `~/.config/wrapit/defaults.wrapit` provides user-level defaults (e.g. SSH agent, git config) that every project inherits unless overridden.
5. **Transparent.** `--dry-run` always shows the exact `bwrap` command that will be executed.
6. **Verifiable.** `--test` runs a standard suite of sandbox integrity checks.
7. **Harness-aware.** `--init` knows about common agent harnesses and proposes sensible defaults per harness.

---

## CLI Interface

```
wrapit [options] <command> [args...]
wrapit --init [--preset <harness>]
wrapit --test
wrapit --dry-run <command> [args...]
wrapit --check
wrapit --version
wrapit --help
```

### Commands

| Invocation | Behaviour |
|---|---|
| `wrapit <cmd> [args]` | Run `<cmd>` sandboxed using `.wrapit` in `$PWD` |
| `wrapit --init` | Interactive guided setup; writes `.wrapit` to `$PWD` |
| `wrapit --init --preset claude-code` | Non-interactive init using a named preset |
| `wrapit --dry-run <cmd> [args]` | Print the resolved `bwrap` command; do not execute |
| `wrapit --test` | Run the 6 sandbox integrity tests against current `.wrapit` |
| `wrapit --check` | Validate `.wrapit` syntax and warn about risky bindings |
| `wrapit --version` | Print version |
| `wrapit --help` | Print usage |

### Examples

```bash
# Run Claude Code sandboxed, passing all flags through
wrapit claude --dangerously-skip-permissions

# Run Aider sandboxed
wrapit aider --model gpt-4o

# Run Gemini CLI sandboxed
wrapit gemini

# See exactly what bwrap command will run, without executing
wrapit --dry-run claude

# Initialise config interactively
wrapit --init

# Initialise config for Gemini CLI without prompts
wrapit --init --preset gemini-cli
```

---

## The `.wrapit` Config File

`.wrapit` is a line-oriented config file similar in spirit to `.gitignore`: one directive per line, `#` comments, blank lines ignored. Unlike `.gitignore`, lines carry an explicit permission prefix.

### Format

```
# Comment (ignored)

# Blank lines are ignored

<permission> <path>

[section]
key = value
```

### Permission Prefixes

| Prefix | Meaning |
|---|---|
| `ro` | Bind mount read-only (`--ro-bind`). Fail if path does not exist. |
| `rw` | Bind mount read/write (`--bind`). Fail if path does not exist. |
| `ro?` | Bind mount read-only, silently skip if path does not exist. |
| `rw?` | Bind mount read/write, silently skip if path does not exist. |

### Directive Order

Directives are applied in the order they appear, and the user defaults file is
applied before the project `.wrapit`. Where two directives cover the same path,
the later one wins, because that is how `bwrap` applies mounts.

This is the supported way to express "writable, except for this":

```ini
rw  ~/.pi                         # the agent needs this tree
ro? ~/.pi/agent/models.json       # ...but must not repoint its own models
ro? ~/.pi/agent/web-search.json   # ...or widen its own network reach
```

Reversing those lines silently gives the agent write access to both files: the
`rw` mount of the parent is applied last and covers them again. `wrapit --check`
warns when a known-sensitive file is left writable this way.

`$PWD` is mounted before any directive from the config, so a `ro` directive can
carve a read-only hole inside the working directory too.

### Path Expansion

Paths support the following expansions:

- `~` → `$HOME`
- `$PWD` → current working directory at invocation time
- `$XDG_CONFIG_HOME` → `~/.config` if unset
- `$XDG_DATA_HOME` → `~/.local/share` if unset
- Environment variables in the form `$VAR` are expanded from the host environment

### Sections

Two optional INI-style sections control sandbox-level behaviour:

```ini
[network]
enabled = true          # true (default) | false

[sandbox]
unshare_pid     = true  # true (default) | false
unshare_ipc     = true  # true (default) | false
unshare_uts     = true  # true (default) | false
unshare_cgroup  = true  # true (default) | false — emitted as --unshare-cgroup-try
die_with_parent = true  # true (default) | false
tmpfs_tmp       = true  # true (default) | false
ssh_agent       = true  # true (default) | false — expose SSH_AUTH_SOCK (never key files)

[env]
clear = false           # false (default) | true — true emits --clearenv
pass  = TZ COLORTERM    # names taken from the parent environment, when set
file  = ~/.config/wrapit/env   # KEY=VALUE lines, expected to be chmod 600
set   = PI_PROFILE=devbox      # a literal value
```

The namespace toggles exist as escape hatches. `wrapit` deliberately does not
use `--unshare-all`, which would also imply `--unshare-user-try` and change how
uids are mapped; the namespaces are named individually instead. `unshare_cgroup`
becomes `--unshare-cgroup-try` so that a kernel without cgroup namespaces
degrades instead of failing the whole sandbox.

#### `[env]`

Without an `[env]` section the sandbox inherits the parent environment in full,
which is how `wrapit` has always behaved and what a hand-written `.wrapit`
depending on an inherited `OPENAI_API_KEY` still expects. It is also the one
place where the tool is not deny-by-default: anything in your shell reaches the
agent, including an `AWS_SECRET_ACCESS_KEY` or a `DATABASE_URL` from a `direnv`
you have forgotten you are in.

`clear = true` emits `--clearenv` and hands back only what is named. **Every
shipped preset sets it**, with each agent's own API keys listed in its `pass`
line, so a config made by `wrapit --init` is deny-by-default and a config
written by hand is not changed under you.

| Key | Meaning |
|---|---|
| `clear` | `true` starts from an empty environment (`--clearenv`). Default `false`. |
| `pass` | Space-separated variable names taken from the parent environment. Names that are unset are skipped silently. Repeatable; values accumulate. |
| `file` | A file of `KEY=VALUE` lines, for secrets that should not be in a committed config. Blank lines and lines starting with `#` are ignored, an `export ` prefix is allowed, and one layer of surrounding quotes is stripped. A mode looser than `600` is warned about. |
| `set` | A literal `KEY=VALUE`. Repeatable. |

`clear = false` with `pass`/`file`/`set` is valid and sometimes what you want:
the environment is inherited *and* the named values are set on top.

Precedence, lowest to highest: the always-present variables below, then `pass`,
then `file`, then `set`. Within a merged config, the project `.wrapit` is applied
after the user defaults, so it wins on `clear` and on any single variable.

### Hardcoded Minimum (not in .wrapit)

The following mounts are always applied regardless of `.wrapit` content. They are the bare minimum for any program to run:

```
--ro-bind /usr /usr
--ro-bind /lib /lib
--ro-bind /lib64 /lib64           (skipped if absent — some distros omit it)
--ro-bind /bin /bin               (skipped if absent — often a symlink to /usr/bin)
--ro-bind /etc/resolv.conf /etc/resolv.conf
--ro-bind /etc/hosts /etc/hosts
--ro-bind /etc/ssl /etc/ssl
--ro-bind /etc/passwd /etc/passwd
--ro-bind /etc/group /etc/group
--ro-bind /etc/nsswitch.conf      (skipped if absent — glibc name resolution)
--ro-bind /etc/alternatives       (skipped if absent — Debian's symlink farm)
--ro-bind /etc/localtime          (skipped if absent — local time, not UTC)
--ro-bind /etc/ca-certificates.conf  (skipped if absent — some TLS stacks read it)
--proc /proc
--dev /dev
--tmpfs /tmp                      (when sandbox.tmpfs_tmp = true)
--setenv HOME "$HOME"
--setenv USER "$USER"
--chdir "$PWD"
```

The four distro-dependent `/etc` entries matter in practice. Without
`nsswitch.conf`, glibc falls back to compiled-in defaults for name resolution
rather than the host's policy. Without `/etc/alternatives`, a Debian
`/usr/bin/node` that is a symlink into the farm has an unreachable target inside
the sandbox. Without `/etc/localtime`, the agent's timestamps are UTC while
yours are not.

`$PWD` is always mounted read/write. It does not need to appear in `.wrapit` (though it may for clarity / documentation purposes; wrapit will deduplicate it).

### SSH Agent

When `sandbox.ssh_agent = true` (the default), wrapit:

1. Checks `$SSH_AUTH_SOCK` is set. If not, prints a warning and skips.
2. Binds the socket's parent directory: `--bind "$(dirname $SSH_AUTH_SOCK)" "$(dirname $SSH_AUTH_SOCK)"`
3. Adds `--setenv SSH_AUTH_SOCK "$SSH_AUTH_SOCK"`
4. Binds `~/.ssh/known_hosts` read-only: `--ro-bind ~/.ssh/known_hosts ~/.ssh/known_hosts` (skipped if absent)

Private key files (`~/.ssh/id_*`) are **never** exposed.

---

## Full `.wrapit` Example (Claude Code)

```ini
# .wrapit — wrapit sandbox configuration
# Generated by: wrapit --init --preset claude-code
# Docs: https://github.com/your-org/wrapit

# ── SSH ──────────────────────────────────────────────────────────────────────
# SSH agent socket is forwarded so git push / clone works.
# Private key files are never exposed — the agent signs requests through
# the host SSH agent without seeing the key material.
[sandbox]
ssh_agent = true

# ── Network ──────────────────────────────────────────────────────────────────
# Allow outbound network access (required for git clone, npm install, etc.).
# Set to false for high-security / air-gapped workflows.
[network]
enabled = true

# ── Environment ──────────────────────────────────────────────────────────────
# Start from an empty environment and name what comes back, so that nothing
# else in the shell — cloud credentials, tokens, a direnv's DATABASE_URL —
# reaches the agent.
[env]
clear = true
pass  = TZ COLORTERM
pass  = ANTHROPIC_API_KEY ANTHROPIC_BASE_URL

# ── Git identity ─────────────────────────────────────────────────────────────
# Read-only: agent can commit with your identity but cannot change git config.
ro  ~/.gitconfig
ro? ~/.config/git

# ── Node.js runtime ──────────────────────────────────────────────────────────
# Read-only: agent can use node/npm from your version manager.
ro? ~/.nvm
ro? ~/.fnm
ro? ~/.volta
ro? ~/.asdf

# ── npm package cache ─────────────────────────────────────────────────────────
# Read/write: cached packages persist across sessions, speeding up npm install.
rw  ~/.npm

# ── Claude Code credentials ───────────────────────────────────────────────────
# Read/write: stores session token so you don't re-authenticate every run.
# Contains only auth tokens, not keys or secrets.
rw  ~/.claude

# ── Project workspace ─────────────────────────────────────────────────────────
# Read/write: the agent works here. Always mounted rw; listed for clarity.
rw  $PWD
```

---

## Global User Defaults

`~/.config/wrapit/defaults.wrapit` is merged before the project `.wrapit`. Project settings take precedence on conflicts (last-write wins on duplicate paths), which follows from [Directive Order](#directive-order) rather than being a special case.

Two consequences worth stating:

- **Keep every binding in this file optional** (`ro?` / `rw?`). A plain `ro` or `rw` naming a path that does not exist is a hard error, and an error here breaks every project on the machine, not just one.
- The file is parsed on every run, so `wrapit --check` scans it alongside the project config, and a `rw` mount that covers it is flagged: an agent that can rewrite your defaults can grant itself wider access the next time you run it.

`WRAPIT_DEFAULTS_FILE` overrides the path, and setting it to the empty string disables the merge entirely. It exists for the test suite, which must not pick up whatever the developer happens to have installed.

Example `defaults.wrapit`:

```ini
# ~/.config/wrapit/defaults.wrapit
# User-level defaults applied to every project.

[sandbox]
ssh_agent       = true
unshare_pid     = true
die_with_parent = true
tmpfs_tmp       = true

[network]
enabled = true

# Every binding here is optional: this file is merged into every project, so a
# missing path would break all of them.
ro? ~/.gitconfig
ro? ~/.config/git
ro? ~/.nvm
ro? ~/.fnm
ro? ~/.volta
rw? ~/.npm
```

---

## Guided Init (`wrapit --init`)

When run, `--init` interactively walks the user through creating `.wrapit`. The wizard:

1. **Detects harness.** Reads the `binary:` frontmatter field of each `.preset` file and checks whether that binary exists in `$PATH`. The list of checked binaries is dynamic — no hardcoded list. Offers detected harnesses as defaults; user can override.
2. **Loads preset.** Applies the preset for the chosen harness as a starting point.
3. **Asks about optional paths.** Prompts for common extras:
   - Python virtualenvs (`~/.pyenv`, `~/.local/lib/python*`, `$VIRTUAL_ENV`)
   - Rust toolchain (`~/.cargo`, `~/.rustup`)
   - Go workspace (`~/go`)
   - Cloud CLIs (`~/.aws`, `~/.config/gcloud`, `~/.azure`) — offered read-only, with a security warning
   - Docker socket — see step 3a; not offered as a generic prompt
3a. **Detects the local dev environment.** `detect_dev_env` looks in `$PWD` for
   `.lando.yml` (and its variants), `.ddev/config.yaml`, `docker-compose.yml` /
   `compose.yml`, a `Dockerfile`, or `.devcontainer/`, and reports `lando`, `ddev`
   and/or `docker`.

   - **Detected:** that tool's paths and `rw? /var/run/docker.sock` are written as
     live directives, with the escape warning above them. A project that needs
     containers needs them on every run, so this is not left as an edit. The
     project's own dev-env config files are pinned with `ro? $PWD/...` *after* the
     `rw $PWD`, because the agent can otherwise rewrite them and make a legitimate
     `lando start` mount anything (see [Directive Order](#directive-order)).
   - **Not detected:** the whole block is written commented out, so opting in is a
     visible edit.

   Every path added this way is optional (`rw?` / `ro?`), so a generated config
   still parses on a machine without Docker installed.
4. **Security scan.** Before writing, scans the proposed config for dangerous bindings (see Security Checks below) and warns. This is where a freshly detected Docker socket is reported, so the user sees it at generation time.
5. **Writes `.wrapit`.** Outputs the file with a comment header explaining each line.
6. **Offers `.gitignore` update.** If a `.gitignore` file exists in `$PWD`, asks the user whether to add `.wrapit` to it. Rationale: `.wrapit` may contain machine-specific path references (e.g. `$HOME`-relative paths resolved at init time, or paths unique to the user's toolchain setup) that would not be meaningful or correct for other contributors. The prompt should explain both sides — committing `.wrapit` is useful for sharing sandbox policy with the team; ignoring it is appropriate when the config is personal or environment-specific. The user decides; wrapit does not default either way.

---

## Built-in Harness Presets

Presets are individual files in the `presets/` directory. Each file has YAML-style frontmatter followed by `.wrapit` directives. The list of available presets is discovered dynamically at runtime — no hardcoded list exists in the code.

### Preset file format

```
---
name: <preset-name>
binary: <binary-to-detect-in-PATH>
description: <human-readable description>
---
# ── Section header ────────────────────────────────────────────────────────────
# One-line explanation of what is mounted and why.
rw  ~/.agent-data
```

Frontmatter fields:

| Field | Required | Description |
|---|---|---|
| `name` | yes | Preset name (must match filename without `.preset`) |
| `binary` | no | Binary name; `detect_harnesses` checks this during `--init` |
| `description` | yes | Shown in `--help` and `--init` harness detection |

The common base (`[sandbox]` settings, `[network]`, `[env] clear = true` with a
non-secret `pass` list, and git identity) is stored in `presets/_base.preset` and
is automatically prepended by `get_preset()`. Individual preset files contain
only agent-specific paths and the `pass` names for that agent's own API keys.

Because `_base.preset` is prepended to *every* preset, anything placed in it is
opted out of rather than into. Nothing belongs there that a given agent might not
want — in particular no sandbox-escape path. Optional project tooling (Lando,
ddev, the Docker socket) lives commented-out in the generated project section
instead, where accepting it is visible in the project's own config.

### Generated `.wrapit` structure

`wrapit --init --preset <name>` writes a `.wrapit` file with this structure:

1. Comment header (`# Generated by: wrapit --init --preset <name>`)
2. Base content (`_base.preset` body — sandbox, network, git identity with section comments)
3. Preset-specific content (agent paths with section comments)
4. Project workspace section (`rw $PWD`, listed for clarity)
5. Project-specific bindings template (commented-out examples for Python, Rust, cloud CLIs, etc.)

### Available presets

| Preset | Binary | Key paths |
|---|---|---|
| `claude-code` | `claude` | `rw ~/.claude`, `rw? ~/.claude.json`, `rw ~/.npm`, `ro? ~/.nvm/fnm/volta/asdf` |
| `aider` | `aider` | `rw ~/.aider` |
| `codex-cli` | `codex` | `rw ~/.codex`, `rw ~/.npm` |
| `opencode` | `opencode` | `rw ~/.config/opencode`, `rw ~/.local/share/opencode`, `rw ~/.npm` |
| `gemini-cli` | `gemini` | `rw ~/.gemini`, `rw ~/.npm` |
| `qwen-code` | `qwen` | `rw ~/.qwen`, `rw ~/.npm` |
| `mistral-vibe` | `vibe` | `rw ~/.vibe`, `ro? ~/.local/bin`, `rw? ~/.cache/uv` |
| `pi` | `pi` | `rw ~/.pi/agent`, `rw ~/.npm` |
| `goose` | `goose` | `rw ~/.config/goose`, `rw ~/.local/share/goose` |
| `amp` | `amp` | `rw ~/.config/amp`, `rw ~/.local/share/amp` |
| `generic` | — | Base only; user adds project-specific paths |

### Adding a new preset

Create `presets/<name>.preset` with the frontmatter above and add `.wrapit` directives for the agent's data directories. Run `wrapit --init --preset <name>` and `wrapit --check` to validate. See `README.md` for full guidance.

---

## Security Checks (`wrapit --check`)

`wrapit --check` (and the final step of `--init`) validates `.wrapit` and emits warnings/errors for dangerous patterns.

### Errors (block execution)

| Pattern | Reason |
|---|---|
| `rw /` | Mounting root read/write defeats the sandbox entirely |
| `rw /etc` | Would allow overwriting system config |
| `rw /usr`, `rw /bin`, `rw /lib*` | Would allow replacing system binaries |
| `rw /home` | Grants write access to all users' home directories |

### Warnings (allow with `--force` or explicit confirmation)

| Pattern | Reason |
|---|---|
| `rw ~/.ssh` | Exposes private key files to the agent |
| `rw ~/.aws`, `rw ~/.azure`, `rw ~/.config/gcloud` | Cloud credentials; prefer `ro` |
| `rw ~/.gnupg` | GPG private keys |
| Any `.env` file binding | May contain API keys or secrets |
| Paths containing `id_rsa`, `id_ed25519`, `id_ecdsa` | SSH private key files |
| `[network] enabled = false` + `rw` on cloud credential dirs | Inconsistent; probably a config mistake |

### Sandbox-escape paths

Reported with a `SANDBOX ESCAPE PATH` label rather than as an ordinary warning,
because these do not widen the sandbox, they end it. Flagged at **any**
permission: a read-only bind of a socket is no defence, the socket is still
there to be spoken to.

| Pattern | Reason |
|---|---|
| `*/docker.sock`, `/var/run/docker`, `/run/docker` | Grants trivial root on the host: anything holding it can start a privileged container that mounts `/` |
| `*/podman.sock` | Lets the agent start containers outside the sandbox |

These are non-blocking, because some projects genuinely need them — a Lando or
ddev workflow does not function without the Docker socket. No *preset* mounts one,
so no agent gets it merely by being that agent; `--init` writes it per project,
only when that project carries container markers, and always with the warning
above it. The decision stays visible in the project's own config, and `--check`
repeats it on every run.

A rootless daemon's socket is the same kind of path with a much smaller blast
radius: abusing it yields the daemon's user rather than host root. `--check` does
not currently distinguish the two, which is a reasonable future refinement — an
allow-listed endpoint that downgrades the label.

### Writable agent config inside an `rw` mount

A directory mounted `rw` may contain a file that lets the agent widen its own
policy for the next run. `--check` keeps a list of such files, resolves which
directive covers each one *last*, and warns when the winner is writable. A `ro`
directive placed after the `rw` mount silences it; the same directive placed
before does not, matching what `bwrap` will actually do.

| File | Why |
|---|---|
| `~/.pi/agent/models.json` | The agent could repoint its own model endpoint |
| `~/.pi/agent/web-search.json` | The agent could widen its own fetch allow-list |
| `~/.config/wrapit/defaults.wrapit` | The agent could grant itself wider access on the next run |

### Info notices (always shown during `--init`)

- If `[network] enabled = true`: remind user that network access means the agent can exfiltrate anything it can read.
- If `$PWD` contains a `.env` file: suggest adding it to `.gitignore` and remind that the agent can read it since `$PWD` is always rw.

---

## Sandbox Integrity Tests (`wrapit --test`)

Runs 6 tests adapted from the blog post. Each test prints `PASS`, `FAIL` or `SKIP` with a short explanation.

| Test | What it checks |
|---|---|
| **T1: Home directory hidden** | `$HOME/.bashrc` and `$HOME/Documents` do not exist inside the sandbox |
| **T2: Read-only paths unwritable** | Appending to the first `ro` file the config mounts under `$HOME` fails. Taken from the config rather than hardcoded, and skipped when the config mounts no such file |
| **T3: Working directory writable** | `touch` then `rm` of a scratch file in `$PWD` succeeds |
| **T4: Process isolation** | `ps aux` shows ≤15 processes; the host has hundreds. The bound allows for the test's own pipeline |
| **T5: /tmp isolation** | A file written to host `/tmp` before the test is not visible inside the sandbox |
| **T6: SSH agent works, key hidden** | `ssh-add -l` succeeds while `~/.ssh/id_ed25519` and `~/.ssh/id_rsa` do not exist (skipped if no key loaded) |

**The harness must not use `eval`.** Each test is a `bash -c` script whose own
quoting has to reach the sandbox intact, and `eval` concatenates its arguments
and re-parses them, which destroys exactly that. The argv is built into an array
by `load_bwrap_argv` and passed as `bwrap "${WRAPIT_BWRAP_ARGV[@]}" "$@"`. Under
`eval`, `bash -c 'test ! -e "$HOME/.bashrc"'` became `bash -c test` with the rest
as positional parameters, `$HOME` was expanded by the host shell, and every check
reported `FAIL` on a sandbox that was working correctly. T2 was worse: its `>>`
redirection was run by the host shell, appending to the real `~/.gitconfig` on
every `--test`. Any path that needs a value interpolated passes it as `$1` rather
than embedding it in the script.

If `[network] enabled = false`, an additional test is run:

| Test | What it checks |
|---|---|
| **T7: No outbound network** | `curl -s --max-time 3 https://example.com` fails or times out |

---

## Implementation Language

`wrapit` is implemented as a **bash script**. This is a deliberate choice: it has zero compile-time dependencies, is trivially auditable, and runs anywhere `bwrap` is available without requiring a runtime or package manager.

**Minimum bash version:** 3.2 (for future macOS compatibility). The script asserts this at startup and exits with a clear error on older versions. No bash 4+ features (`declare -A`, `mapfile`, `${var,,}`) are used.

**Runtime dependencies** (checked at startup; clear error if missing):
- `bwrap` — sandboxing engine
- `bash` ≥ 3.2
- Standard POSIX tools: `grep`, `sed`, `awk`, `cut`, `dirname`, `realpath`, `mktemp`

---

## Repository Layout

```
wrapit/
├── wrapit                  # Main executable bash script
├── install.sh              # User installation script
├── uninstall.sh            # Removes installed files and shell aliases
├── lib/
│   ├── parse.sh            # .wrapit config parser
│   ├── build_bwrap.sh      # Assembles the bwrap argv array
│   ├── presets.sh          # File-based preset loader (WRAPIT_PRESETS_DIR)
│   ├── init.sh             # --init wizard logic
│   ├── check.sh            # --check security scanner
│   └── test.sh             # --test sandbox integrity tests
├── presets/
│   ├── _base.preset        # Common base (sandbox, network, git identity)
│   ├── claude-code.preset  # Claude Code preset
│   ├── aider.preset        # Aider preset
│   ├── ...                 # One .preset file per supported harness
│   └── generic.preset      # Generic (base only)
├── tests/
│   ├── test_parse.bats     # Parser unit tests
│   ├── test_build_bwrap.bats  # bwrap arg builder tests
│   ├── test_check.bats     # Security checker tests
│   ├── test_init.bats      # Init wizard tests (non-interactive paths)
│   ├── test_presets.bats   # Preset loader and content tests
│   └── test_integration.bats  # End-to-end sandbox tests (require bwrap)
├── fixtures/
│   ├── claude-code.wrapit  # Example .wrapit files used by tests
│   ├── minimal.wrapit
│   ├── dangerous.wrapit
│   └── ...
└── README.md
```

The main `wrapit` script sources the `lib/` files at startup using paths relative to the script's own location (resolved via `BASH_SOURCE[0]`), so the entire `wrapit/` directory can be placed anywhere on disk.

---

## Installation (`install.sh`)

`install.sh` installs `wrapit` for the current user only. It does **not** require `sudo`.

### What it does

1. **Checks prerequisites.** Verifies `bash` ≥ 3.2 and `bwrap` are installed. Prints install instructions for the user's distro if `bwrap` is missing (detects via `/etc/os-release`: apt / dnf / pacman / zypper).
2. **Copies files.** Copies `wrapit`, `lib/`, and `presets/` to `~/.local/share/wrapit/`.
3. **Creates the executable symlink** (or wrapper) at `~/.local/bin/wrapit`, pointing to `~/.local/share/wrapit/wrapit`. Creates `~/.local/bin/` if it does not exist.
4. **Updates shell config**, unless `--no-path` is given. Detects the user's active shell(s) by inspecting `$SHELL` and checking for the existence of `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`. For each found config file, appends a `PATH` export block if `~/.local/bin` is not already on `$PATH`:
   ```bash
   # wrapit — added by wrapit install.sh
   export PATH="$HOME/.local/bin:$PATH"
   ```
   The block is idempotent: `install.sh` checks for the comment marker before appending, so re-running it is safe.

   `--no-path` skips this entirely and prints the line to add by hand. It exists
   for managed dotfiles: a `~/.zshrc` generated from a template loses an
   appended block on the next regeneration, silently, and the user additions
   belong in whatever file that setup keeps them in (`~/.zshrc.local` and the
   like).
5. **Creates the user defaults file.** Writes `~/.config/wrapit/defaults.wrapit` if it does not already exist, populated with sensible defaults (git config, SSH agent, npm cache), all as optional bindings — see [Global User Defaults](#global-user-defaults).
6. **Prints a success summary** listing every action taken, the detected shell(s), and instructions to `source ~/.bashrc` (or equivalent) or open a new terminal.

### What it does NOT do

- Does not modify `/etc/` or any system-wide files.
- Does not run as root.
- Does not modify other users' environments.
- Does not add anything beyond the `PATH` export to shell configs — no `alias` lines, no `eval` hooks.

### Invocation

`install.sh` needs the source tree beside it — it copies `wrapit`, `lib/` and
`presets/` out of its own directory — so installing means cloning first. There is
deliberately **no `curl | bash` one-liner**: a tool whose job is to confine an
agent is a poor candidate for an install path that pipes an unread script into a
shell. It is worth saying so, since a one-liner is the usual expectation.

```bash
git clone https://github.com/your-org/wrapit.git
cd wrapit
bash install.sh

# or, when your dotfiles are generated and must not be appended to:
bash install.sh --no-path
```

### `uninstall.sh`

Removes `~/.local/share/wrapit/`, `~/.local/bin/wrapit`, and the `PATH` block from any shell configs it previously modified (identified by the `# wrapit — added by wrapit install.sh` marker). Prompts before removing `~/.config/wrapit/` (the user's defaults file), defaulting to keeping it.

---

## Testing with BATS

All tests are written using [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core). BATS is the standard testing framework for bash scripts and is available via package managers on all major Linux distros.

### Installing BATS

```bash
# Ubuntu / Debian
apt install bats

# Fedora / RHEL
dnf install bats

# Arch
pacman -S bash-bats

# Or via git (for latest version)
git clone https://github.com/bats-core/bats-core.git
./bats-core/install.sh ~/.local
```

### Running Tests

```bash
# All tests
bats tests/

# Single file
bats tests/test_parse.bats

# Integration tests only (requires bwrap)
bats tests/test_integration.bats

# Verbose output
bats --verbose-run tests/
```

### Test File Conventions

Each BATS file follows this structure:

```bash
#!/usr/bin/env bats
# tests/test_parse.bats — unit tests for .wrapit config parsing

setup() {
  # Load the module under test
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  # Create a temp dir for each test
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "ro directive is parsed correctly" {
  echo "ro ~/.gitconfig" > "$TMPDIR/.wrapit"
  run parse_wrapit "$TMPDIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--ro-bind"* ]]
  [[ "${output}" == *".gitconfig"* ]]
}

@test "unknown permission prefix is rejected" {
  echo "xx ~/.gitconfig" > "$TMPDIR/.wrapit"
  run parse_wrapit "$TMPDIR/.wrapit"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"unknown permission"* ]]
}
```

### Test Coverage Requirements

| Test file | What it must cover |
|---|---|
| `test_parse.bats` | `ro`, `rw`, `ro?`, `rw?` directives; `[section]` blocks; comments and blank lines; path expansion (`~`, `$PWD`, `$VAR`); error on unknown prefixes; error on malformed lines |
| `test_build_bwrap.bats` | Correct `--ro-bind` / `--bind` flags; hardcoded minimum mounts always present; `--tmpfs /tmp` toggled by `sandbox.tmpfs_tmp`; SSH agent args when `ssh_agent = true`; `--share-net` / `--unshare-net` based on `[network]`; `--unshare-pid` and `--die-with-parent` flags; deduplication of `$PWD` |
| `test_check.bats` | All error patterns produce exit 1; all warning patterns produce correct output; clean config produces exit 0; `--force` bypasses warnings |
| `test_init.bats` | `--preset <name>` flag writes correct `.wrapit`; non-interactive mode (`--preset` without TTY) does not hang; `.gitignore` updated when user confirms; `.gitignore` unchanged when user declines; correct harness detection output given mock `$PATH` |
| `test_presets.bats` | Frontmatter parsing (`_parse_frontmatter`, `_preset_body`); dynamic discovery (`list_presets`); `get_preset` loads from file and prepends base; content tests for each known preset are guarded with `_skip_if_no_preset` so the suite passes even when a preset file is absent; bulk validity check iterates over all available presets dynamically |
| `test_integration.bats` | T1–T6 pass against a real `bwrap` invocation; `--dry-run` produces valid `bwrap` invocation that can be executed by bash; sandboxed home dir does not expose host `~/.bashrc`; sandboxed `/tmp` does not expose host `/tmp`; process namespace isolated |

Integration tests are tagged with `# bats:require-bwrap` in a comment and are skipped automatically (with a clear `SKIP` message) if `bwrap` is not in `$PATH`, allowing the unit test suite to run in CI environments without bubblewrap.

---

## Error Handling

| Situation | Behaviour |
|---|---|
| No `.wrapit` in `$PWD` or any parent directory | Error: "No .wrapit file found. Run `wrapit --init` to create one." |
| `.wrapit` parse error | Error with line number and description |
| A non-optional `ro`/`rw` path does not exist | Error: "Path does not exist: <path>. Use `ro?`/`rw?` if this path is optional." |
| `bwrap` not found | Error: "bwrap not found. Install bubblewrap: `apt install bubblewrap` / `dnf install bubblewrap`" |
| `--check` finds errors | Exit code 1; print all errors and warnings |
| `--check` finds only warnings | Exit code 0; print warnings |

---

## `.wrapit` Discovery

`wrapit` searches for `.wrapit` starting from `$PWD` and walking up to the filesystem root, similar to how `git` finds `.git`. The first `.wrapit` found wins. This allows a `.wrapit` in a parent workspace to cover multiple sub-projects.

---

## Environment Variables Passed Through

The following host environment variables are always forwarded into the sandbox:

- `HOME`
- `USER`
- `SHELL` (read-only — agent cannot change the host shell)
- `TERM`
- `LANG`, `LC_ALL`
- `SSH_AUTH_SOCK` (when `ssh_agent = true`)
- `PATH` (from the host, so the agent finds the same binaries)

Everything else depends on `[env]`. With no `[env] clear = true`, the rest of the
parent environment is inherited as well; with it, the list above is all the
sandbox starts with, plus whatever `pass`, `file` and `set` name. See
[`[env]`](#env).

---

## Known Limitations

- **Linux only.** `bwrap` is not available on macOS or Windows. macOS support via `sandbox-exec` is a future consideration.
- **No network namespace filtering.** `wrapit` uses `--share-net` (full network access) or no network at all. Domain allowlisting is not currently supported by bubblewrap without an additional tool (e.g. a DNS proxy or firewall rule).
- **No GPU passthrough.** Sandboxed agents cannot access GPU devices. This affects locally-run models.
- **No user namespace nesting.** Sandboxed agents cannot themselves spawn further `bwrap` sandboxes unless the kernel allows nested user namespaces.
- **Docker-in-sandbox.** No preset mounts the Docker daemon socket, and `--check` flags it as a sandbox-escape path wherever it appears, but nothing blocks a config that opts into it. A project that needs containers takes the trade explicitly, in its own `.wrapit`.
- **Bind paths may not contain spaces.** `build_bwrap_args` emits one flag per line and the argv loader splits on the first space, so a source path with a space in it is mis-split. `--setenv` values are exempt: the final operand of a line runs to the end of it, so environment values may contain spaces.

---

## Future Considerations

- `wrapit run --profile <name>` — allow multiple named `.wrapit` files (e.g. `.wrapit.strict`, `.wrapit.dev`)
- `wrapit audit` — scan `.wrapit` history via git for regressions in sandbox permissions
- macOS backend via `sandbox-exec` profiles
- DNS allowlist support via an embedded DNS proxy
- `wrapit update-presets` — pull the latest preset definitions from a central registry

---

## Appendix: Config Path Reference by Harness

| Harness | Binary | Auth/Config Dir | Notes |
|---|---|---|---|
| Claude Code | `claude` | `~/.claude` (rw) | npm cache: `~/.npm` |
| Aider | `aider` | `~/.aider` (rw) | |
| Codex CLI | `codex` | `~/.codex` (rw) | npm cache: `~/.npm` |
| OpenCode | `opencode` | `~/.config/opencode` (rw) | Also `~/.local/share/opencode` |
| Gemini CLI | `gemini` | `~/.gemini` (rw) | npm cache: `~/.npm` |
| Qwen Code | `qwen` | `~/.qwen` (rw) | Fork of Gemini CLI |
| Mistral Vibe | `vibe` | `~/.vibe` (rw) | uv cache: `~/.cache/uv` |
| Pi | `pi` | `~/.pi/agent` (rw) | Overrideable via `$PI_CODING_AGENT_DIR` |
| Goose | `goose` | `~/.config/goose` (rw) | Also `~/.local/share/goose` |
| Amp | `amp` | `~/.config/amp` (rw) | Also `~/.local/share/amp` |
