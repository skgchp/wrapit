#!/usr/bin/env bash
# lib/init.sh — --init wizard logic

# detect_harnesses
# Prints one preset name per line for each preset whose binary is found in $PATH.
# Reads binary field from frontmatter of each .preset file.
detect_harnesses() {
  local f binary preset
  for f in "$WRAPIT_PRESETS_DIR"/*.preset; do
    [ -f "$f" ] || continue
    preset="${f##*/}"
    preset="${preset%.preset}"
    case "$preset" in
      _*) continue ;;
    esac
    binary="$(_parse_frontmatter "$f" "binary")"
    [ -n "$binary" ] || continue
    if command -v "$binary" > /dev/null 2>&1; then
      printf '%s\n' "$preset"
    fi
  done
}

# run_init_gitignore <gitignore_file>
# Asks user whether to add .wrapit to the given .gitignore file.
# Reads answer from stdin. Safe to call non-interactively (EOF = no).
run_init_gitignore() {
  local gitignore_file="$1"

  [ ! -f "$gitignore_file" ] && return 0

  # Already listed — nothing to do
  if grep -q '\.wrapit' "$gitignore_file" 2>/dev/null; then
    return 0
  fi

  printf '\nAdd .wrapit to %s? [y/N] ' "$gitignore_file" >&2
  local answer
  if IFS= read -r answer 2>/dev/null; then
    case "$answer" in
      [Yy]|[Yy][Ee][Ss])
        printf '.wrapit\n' >> "$gitignore_file"
        printf 'Added .wrapit to %s\n' "$gitignore_file" >&2
        ;;
    esac
  fi
}

# detect_dev_env [dir]
# Prints one tool name per line — lando, ddev, docker — for each local dev
# environment this project appears to use, based on the files it carries.
detect_dev_env() {
  local dir="${1:-$PWD}"
  local f

  for f in .lando.yml .lando.yaml .lando.local.yml .lando.dist.yml .lando.base.yml; do
    if [ -f "$dir/$f" ]; then
      printf 'lando\n'
      break
    fi
  done

  if [ -f "$dir/.ddev/config.yaml" ] || [ -f "$dir/.ddev/config.yml" ] || [ -d "$dir/.ddev" ]; then
    printf 'ddev\n'
  fi

  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml Dockerfile .devcontainer; do
    if [ -e "$dir/$f" ]; then
      printf 'docker\n'
      break
    fi
  done
}

# _section_header <title>
# Prints a "# ── Title ─────…" header padded to the 80-column width the other
# section comments use.
_section_header() {
  local title="$1"
  # Counted from the ASCII title only: ${#} on a string containing ── would
  # count bytes or characters depending on the locale. "# ── " plus a trailing
  # space is 6 columns, and the other headers in this file are 81 wide.
  local n=$(( 81 - 6 - ${#title} ))
  local rule=""
  while [ "$n" -gt 0 ]; do
    rule="${rule}─"
    n=$((n - 1))
  done
  printf '# ── %s %s\n' "$title" "$rule"
}

# _dev_env_contains <needle> <space-separated list>
_dev_env_contains() {
  local needle="$1" list="$2" item
  for item in $list; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# _dev_env_section
# Prints the local dev environment bindings. When $PWD carries the markers for
# Lando, ddev or plain Docker the directives are written live, because a project
# that needs containers needs them on every run; otherwise the whole block is
# written commented-out so that opting in stays a visible edit.
#
# The Docker socket is included when detected. It is a sandbox escape and the
# comment says so; `wrapit --check` flags it on every run.
_dev_env_section() {
  local detected pretty
  detected="$(detect_dev_env | tr '\n' ' ')"
  detected="${detected% }"
  # "lando docker" reads badly in prose; "lando, docker" does not.
  pretty="$(printf '%s' "$detected" | sed 's/ /, /g')"

  if [ -z "$detected" ]; then
    _dev_env_section_commented
    return 0
  fi

  local want_lando=false want_ddev=false
  _dev_env_contains lando "$detected" && want_lando=true
  _dev_env_contains ddev "$detected" && want_ddev=true

  printf '\n'
  _section_header "Local dev environments ($pretty)"
  printf '# Written live by `wrapit --init`: this project carries the markers for %s,\n' "$pretty"
  printf '# and a project that needs containers needs them on every run. Delete this\n'
  printf '# section if the detection was wrong.\n'
  printf '#\n'

  if [ "$want_lando" = "true" ]; then
    printf '# Lando installs versioned binaries to ~/.cache/lando/<ver>/bin/lando and\n'
    printf '# symlinks ~/.lando/bin/lando to the active version — both directories must be\n'
    printf '# mounted or the symlink target is unreachable inside the sandbox.\n'
    printf 'rw? ~/.lando\n'
    printf 'rw? ~/.cache/lando\n'
  fi

  if [ "$want_ddev" = "true" ]; then
    printf '# ddev itself is /usr/bin/ddev, covered by the hardcoded /usr ro mount; this is\n'
    printf '# its global config and runtime state. The mkcert CA is what makes ddev-issued\n'
    printf '# https certificates trusted inside the sandbox.\n'
    printf 'rw? ~/.ddev\n'
    printf 'ro? ~/.local/share/mkcert\n'
  fi

  printf '# Docker CLI config: contexts, credential helper settings, buildx state.\n'
  printf 'rw? ~/.docker\n'
  printf '\n'
  printf '# WARNING — the Docker socket is a sandbox escape, not an ordinary mount.\n'
  printf '# Anything holding it can start a privileged container that mounts the host\n'
  printf '# filesystem, which is trivial root on this machine: it undoes every other line\n'
  printf '# in this file. It is here because this project cannot run its dev environment\n'
  printf '# without it, not because it is safe. `wrapit --check` flags it every run.\n'
  printf '#\n'
  printf '# To shrink the blast radius, point this at a ROOTLESS daemon instead — abusing\n'
  printf '# that socket yields the daemon user, not host root — and set DOCKER_HOST to\n'
  printf '# match:\n'
  printf '#\n'
  printf '#   rw? $XDG_RUNTIME_DIR/docker.sock\n'
  printf '#   [env]\n'
  printf '#   set = DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock\n'
  printf '#\n'
  printf 'rw? /var/run/docker.sock\n'

  # The dev environment's own config lives in $PWD, which the agent can write,
  # so a legitimate `lando start` can be made to mount anything. Pin the files
  # read-only where they exist: later directives win over the rw $PWD above.
  local pinned=false
  local f
  for f in .lando.yml .lando.yaml .lando.local.yml .lando.dist.yml .lando.base.yml \
           docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [ -f "$PWD/$f" ]; then
      if [ "$pinned" = "false" ]; then
        printf '\n'
        printf '# The dev environment reads its config from this project directory, which the\n'
        printf '# agent can write — so an edit to one of these files turns a legitimate\n'
        printf '# `lando start` or `docker compose up` into "mount anything, run anything".\n'
        printf '# Pinned read-only here: later directives win over the rw $PWD above.\n'
        printf '# Comment these out if the agent genuinely needs to edit them.\n'
        pinned=true
      fi
      printf 'ro? $PWD/%s\n' "$f"
    fi
  done
  if [ -d "$PWD/.ddev" ]; then
    if [ "$pinned" = "false" ]; then
      printf '\n'
      printf '# The dev environment reads its config from this project directory, which the\n'
      printf '# agent can write — so an edit to it turns a legitimate `ddev start` into\n'
      printf '# "mount anything, run anything". Pinned read-only here: later directives win\n'
      printf '# over the rw $PWD above. Comment it out if the agent needs to edit it.\n'
    fi
    printf 'ro? $PWD/.ddev/config.yaml\n'
  fi
}

# _dev_env_section_commented
# The opt-in form, written when no dev environment was detected.
_dev_env_section_commented() {
  cat <<'EOF'

# ── Local dev environments (Lando / ddev / Docker) ─────────────────────────────
# Nothing in this project looked like it uses containers, so this is opt-in.
# Uncomment for Lando or ddev work — and read the warning first.
#
# Lando installs versioned binaries to ~/.cache/lando/<ver>/bin/lando and
# symlinks ~/.lando/bin/lando to the active version — both directories must be
# mounted or the symlink target is unreachable inside the sandbox.
# ddev uses /usr/bin/ddev (covered by the hardcoded /usr ro mount).
#
# rw? ~/.lando
# rw? ~/.cache/lando
# rw? ~/.ddev
# rw? ~/.docker
#
# WARNING — the Docker socket is a sandbox escape, not an ordinary mount.
# Anything holding it can start a privileged container that mounts the host
# filesystem, which is trivial root on this machine: it undoes every other line
# in this file. Uncomment it only if this project genuinely runs dev-environment
# commands, and know that you are trading the sandbox for them. A rootless
# daemon's socket is a much smaller blast radius. `wrapit --check` flags it.
#
# rw? /var/run/docker.sock
EOF
}

# _project_specific_section
# Prints a commented-out project-specific bindings template.
_project_specific_section() {
  cat <<'EOF'

# ── Project workspace ──────────────────────────────────────────────────────────
# $PWD is always mounted rw automatically; listed here for clarity.
rw  $PWD

# ── Project-specific bindings ──────────────────────────────────────────────────
# Add paths specific to this project that are not covered by the preset above.
# Later directives win over earlier ones, so a ro line below can carve a
# read-only hole in an rw mount made above it.
# See README.md for guidance on what to add here.
#
# Examples:
#   rw? ~/.pyenv              # Python version manager
#   rw? ~/.cargo              # Rust toolchain
#   ro  ~/.aws                # AWS credentials (read-only)
EOF

  _dev_env_section

  cat <<'EOF'

# ── Environment ────────────────────────────────────────────────────────────────
# The preset above starts the sandbox with an empty environment and passes back
# only what it names. Add anything else this project needs:
#
# [env]
# pass  = DATABASE_URL           # taken from your shell, when it is set
# file  = ~/.config/wrapit/env   # KEY=VALUE lines, chmod 600 — for secrets
# set   = NODE_ENV=development   # a fixed value, whatever your shell holds
#
# Setting `clear = false` here would hand the agent your entire shell
# environment instead. It is supported, for hand-written configs that relied on
# it, but it means every credential in your shell reaches the agent.
EOF
}

# run_init [--preset <name>]
# Writes a .wrapit file to $PWD.
# With --preset: non-interactive, uses the named preset.
# Without --preset: interactive wizard.
run_init() {
  local preset_name=""
  local force=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --preset)
        shift
        preset_name="${1:-}"
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local out_file="$PWD/.wrapit"

  if [ -n "$preset_name" ]; then
    local preset_content
    preset_content="$(get_preset "$preset_name")" || return 1

    if [ -f "$out_file" ] && [ ! -t 0 ]; then
      printf 'wrapit: %s already exists; refusing to overwrite in non-interactive mode\n' \
        "$out_file" >&2
      return 1
    fi

    if [ -f "$out_file" ] && [ -t 0 ]; then
      printf '%s already exists. Overwrite? [y/N] ' "$out_file" >&2
      local ans
      IFS= read -r ans
      case "$ans" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *) printf 'Aborted.\n' >&2; return 1 ;;
      esac
    fi

    {
      printf '# .wrapit — wrapit sandbox configuration\n'
      printf '# Generated by: wrapit --init --preset %s\n' "$preset_name"
      printf '#\n'
      printf '%s\n' "$preset_content"
      _project_specific_section
    } > "$out_file"

    check_wrapit "$out_file" 2>/dev/null || true

    run_init_gitignore "$PWD/.gitignore"

    printf 'Wrote %s\n' "$out_file" >&2
    return 0
  fi

  # Interactive mode
  local detected
  detected="$(detect_harnesses)"

  if [ -n "$detected" ]; then
    printf 'Detected AI harnesses on your PATH:\n' >&2
    printf '%s\n' "$detected" | while IFS= read -r p; do
      printf '  - %s\n' "$p" >&2
    done
  fi

  printf '\nWhich preset would you like to use? [claude-code] ' >&2
  local chosen
  if IFS= read -r chosen 2>/dev/null && [ -n "$chosen" ]; then
    preset_name="$chosen"
  else
    preset_name="$(printf '%s' "$detected" | head -1)"
    [ -z "$preset_name" ] && preset_name="claude-code"
  fi

  run_init --preset "$preset_name"
}
