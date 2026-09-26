#!/usr/bin/env bash
# lib/build_bwrap.sh — assembles the bwrap argv array

# _add_ro_bind_if_exists <path>
_add_ro_bind_if_exists() {
  [ -e "$1" ] && printf -- '--ro-bind %s %s\n' "$1" "$1"
}

# _emit_bind <flag> <src> [dest]
# Emits a bind directive, prepending --dir DEST when the destination is under
# a tmpfs (i.e. /tmp) to ensure the mount point exists.
_emit_bind() {
  local flag="$1"   # --ro-bind or --bind
  local src="$2"
  local dest="${3:-$2}"
  local tmpfs_root="${_WRAPIT_TMPFS_ROOT:-}"

  if [ -n "$tmpfs_root" ]; then
    case "$dest" in
      "${tmpfs_root}"/*|"${tmpfs_root}")
        printf -- '--dir %s\n' "$dest"
        ;;
    esac
  fi
  printf -- '%s %s %s\n' "$flag" "$src" "$dest"
}

# build_bwrap_args <config_file>
# Outputs the complete bwrap argument list, one logical group per line.
build_bwrap_args() {
  local config_file="$1"

  # Parse config — sets WRAPIT_* globals, writes user binding args to temp file
  local tmp_bindings
  tmp_bindings="$(mktemp)"
  parse_wrapit "$config_file" > "$tmp_bindings" || { rm -f "$tmp_bindings"; return 1; }

  # Determine which tmpfs roots we'll add (only /tmp for now)
  local tmpfs_tmp="${WRAPIT_SANDBOX_TMPFS_TMP:-true}"

  # Expose the tmpfs root to _emit_bind
  if [ "$tmpfs_tmp" = "true" ]; then
    _WRAPIT_TMPFS_ROOT="/tmp"
  else
    _WRAPIT_TMPFS_ROOT=""
  fi

  # ── Hardcoded system mounts (non-/tmp) ──────────────────────────────────
  printf -- '--ro-bind /usr /usr\n'
  printf -- '--ro-bind /lib /lib\n'
  _add_ro_bind_if_exists /lib64
  _add_ro_bind_if_exists /bin
  printf -- '--ro-bind /etc/resolv.conf /etc/resolv.conf\n'
  printf -- '--ro-bind /etc/hosts /etc/hosts\n'
  printf -- '--ro-bind /etc/ssl /etc/ssl\n'
  printf -- '--ro-bind /etc/passwd /etc/passwd\n'
  printf -- '--ro-bind /etc/group /etc/group\n'
  printf -- '--proc /proc\n'
  printf -- '--dev /dev\n'

  # ── tmpfs mounts (must come before any bind mounts under them) ──────────
  if [ "$tmpfs_tmp" = "true" ]; then
    printf -- '--tmpfs /tmp\n'
  fi

  # ── User-specified bindings ─────────────────────────────────────────────
  local pwd_already_bound=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local flag src dest
    flag="${line%% *}"
    local rest="${line#* }"
    src="${rest%% *}"
    dest="${rest#* }"
    case "$line" in
      "--bind $PWD $PWD") pwd_already_bound=true ;;
    esac
    _emit_bind "$flag" "$src" "$dest"
  done < "$tmp_bindings"
  rm -f "$tmp_bindings"

  # ── $PWD always rw (deduplicated) ───────────────────────────────────────
  if [ "$pwd_already_bound" = "false" ]; then
    _emit_bind "--bind" "$PWD" "$PWD"
  fi

  # ── SSH agent ────────────────────────────────────────────────────────────
  if [ "${WRAPIT_SANDBOX_SSH_AGENT:-true}" = "true" ]; then
    if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -e "$SSH_AUTH_SOCK" ]; then
      local sock_dir
      sock_dir="$(dirname "$SSH_AUTH_SOCK")"
      _emit_bind "--bind" "$sock_dir" "$sock_dir"
      printf -- '--setenv SSH_AUTH_SOCK %s\n' "$SSH_AUTH_SOCK"
      if [ -e "$HOME/.ssh/known_hosts" ]; then
        _emit_bind "--ro-bind" "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts"
      fi
    else
      printf 'warning: ssh_agent=true but $SSH_AUTH_SOCK is not set or does not exist; skipping SSH agent\n' >&2
    fi
  fi

  # ── Network ──────────────────────────────────────────────────────────────
  # bwrap does NOT unshare the network namespace by default; must be explicit.
  if [ "${WRAPIT_NETWORK_ENABLED:-true}" = "true" ]; then
    printf -- '--share-net\n'
  else
    printf -- '--unshare-net\n'
  fi

  # ── PID and parent flags ─────────────────────────────────────────────────
  if [ "${WRAPIT_SANDBOX_UNSHARE_PID:-true}" = "true" ]; then
    printf -- '--unshare-pid\n'
  fi

  if [ "${WRAPIT_SANDBOX_DIE_WITH_PARENT:-true}" = "true" ]; then
    printf -- '--die-with-parent\n'
  fi

  # ── Always-present environment ──────────────────────────────────────────
  printf -- '--setenv HOME %s\n' "$HOME"
  printf -- '--setenv USER %s\n' "$USER"
  printf -- '--setenv PATH %s\n' "$PATH"
  printf -- '--setenv TERM %s\n' "${TERM:-xterm}"
  printf -- '--setenv LANG %s\n' "${LANG:-C}"
  if [ -n "${LC_ALL:-}" ]; then
    printf -- '--setenv LC_ALL %s\n' "$LC_ALL"
  fi
  if [ -n "${SHELL:-}" ]; then
    printf -- '--setenv SHELL %s\n' "$SHELL"
  fi

  printf -- '--chdir %s\n' "$PWD"
}
