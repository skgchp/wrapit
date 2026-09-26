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

# wrapit_defaults_file
# Prints the path to the user-level defaults file, or nothing when the user has
# explicitly disabled it by setting WRAPIT_DEFAULTS_FILE to the empty string.
wrapit_defaults_file() {
  if [ -n "${WRAPIT_DEFAULTS_FILE+set}" ]; then
    printf '%s' "$WRAPIT_DEFAULTS_FILE"
    return 0
  fi
  printf '%s/wrapit/defaults.wrapit' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# _file_mode <path>
# Prints the octal permission bits of a file (GNU stat, with a BSD fallback).
_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

# _emit_env_pass
# Emits --setenv for each name in WRAPIT_ENV_PASS that is set in the parent
# environment. Names that are unset are skipped silently.
_emit_env_pass() {
  [ -n "$WRAPIT_ENV_PASS" ] || return 0
  local name value
  local old_ifs="$IFS"
  IFS=' '
  # shellcheck disable=SC2086
  set -- $WRAPIT_ENV_PASS
  IFS="$old_ifs"
  for name in "$@"; do
    [ -n "$name" ] || continue
    # Strict validation: the name is interpolated into an eval below, so
    # anything that is not a plain identifier is rejected outright.
    case "$name" in
      *[!A-Za-z0-9_]*|[0-9]*)
        printf 'warning: [env] pass: not a valid variable name, ignoring: %s\n' "$name" >&2
        continue
        ;;
    esac
    eval "value=\"\${${name}+set}\"" 2>/dev/null || value=""
    [ "$value" = "set" ] || continue
    eval "value=\"\$${name}\""
    printf -- '--setenv %s %s\n' "$name" "$value"
  done
}

# _emit_env_file
# Emits --setenv for each KEY=VALUE line in the file named by [env] file.
# Lines whose first non-blank character is # are comments; values are not
# comment-stripped, since a secret may legitimately contain a # character.
_emit_env_file() {
  [ -n "$WRAPIT_ENV_FILE" ] || return 0
  local env_file
  env_file="$(_expand_path "$WRAPIT_ENV_FILE")"

  if [ ! -f "$env_file" ]; then
    printf 'wrapit: [env] file not found: %s\n' "$env_file" >&2
    return 1
  fi

  # The file holds secrets, so anything group- or world-readable is worth
  # flagging. Non-blocking: the user may have deliberate reasons.
  local mode
  mode="$(_file_mode "$env_file")"
  case "$mode" in
    ""|*00) ;;
    *) printf 'warning: [env] file %s is mode %s; 600 is recommended\n' "$env_file" "$mode" >&2 ;;
  esac

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(_trim "$line")"
    [ -z "$line" ] && continue
    case "$line" in
      "#"*) continue ;;
    esac
    # Allow an optional "export " prefix so a sourceable file also works here.
    case "$line" in
      "export "*) line="$(_trim "${line#export }")" ;;
    esac
    case "$line" in
      *"="*) ;;
      *)
        printf 'warning: [env] file %s: ignoring line without "=": %s\n' "$env_file" "$line" >&2
        continue
        ;;
    esac
    key="$(_trim "${line%%=*}")"
    value="${line#*=}"
    # Strip one layer of matching surrounding quotes, as .env files often use them.
    case "$value" in
      '"'*'"') value="${value#\"}"; value="${value%\"}" ;;
      "'"*"'") value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf -- '--setenv %s %s\n' "$key" "$value"
  done < "$env_file"
}

# _emit_env_set
# Emits --setenv for each KEY=VALUE entry given by [env] set.
_emit_env_set() {
  [ -n "$WRAPIT_ENV_SET" ] || return 0
  local entry key value
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    key="$(_trim "${entry%%=*}")"
    value="${entry#*=}"
    printf -- '--setenv %s %s\n' "$key" "$value"
  done <<EOF
$WRAPIT_ENV_SET
EOF
}

# build_bwrap_args <config_file>
# Outputs the complete bwrap argument list, one logical group per line.
#
# Ordering is significant and is part of the documented contract: bwrap applies
# mount operations in the order given, so a later directive wins over an earlier
# one covering the same path. That is what makes "rw a directory, then ro a file
# inside it" work.
build_bwrap_args() {
  local config_file="$1"

  # Parse config — sets WRAPIT_* globals, writes user binding args to temp file.
  # The user-level defaults file is parsed first so that the project .wrapit
  # wins on conflicting settings and on overlapping paths.
  local tmp_bindings
  tmp_bindings="$(mktemp)" || return 1
  local defaults_file
  defaults_file="$(wrapit_defaults_file)"

  reset_wrapit_globals
  if [ -n "$defaults_file" ] && [ -f "$defaults_file" ]; then
    parse_wrapit "$defaults_file" --keep-globals >> "$tmp_bindings" || {
      rm -f "$tmp_bindings"
      return 1
    }
  fi
  parse_wrapit "$config_file" --keep-globals >> "$tmp_bindings" || {
    rm -f "$tmp_bindings"
    return 1
  }

  # Determine which tmpfs roots we'll add (only /tmp for now)
  local tmpfs_tmp="${WRAPIT_SANDBOX_TMPFS_TMP:-true}"

  # Expose the tmpfs root to _emit_bind
  if [ "$tmpfs_tmp" = "true" ]; then
    _WRAPIT_TMPFS_ROOT="/tmp"
  else
    _WRAPIT_TMPFS_ROOT=""
  fi

  # ── Environment ─────────────────────────────────────────────────────────
  # --clearenv must precede every --setenv, so it goes first of all.
  if [ "${WRAPIT_ENV_CLEAR:-false}" = "true" ]; then
    printf -- '--clearenv\n'
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
  # Distro-dependent, bound when present:
  #   nsswitch.conf        glibc reads it to decide how to resolve names
  #   alternatives         Debian's symlink farm; /usr/bin/node & co. point into it
  #   localtime            without it the agent's timestamps are UTC
  #   ca-certificates.conf some TLS stacks read it alongside /etc/ssl
  _add_ro_bind_if_exists /etc/nsswitch.conf
  _add_ro_bind_if_exists /etc/alternatives
  _add_ro_bind_if_exists /etc/localtime
  _add_ro_bind_if_exists /etc/ca-certificates.conf
  printf -- '--proc /proc\n'
  printf -- '--dev /dev\n'

  # ── tmpfs mounts (must come before any bind mounts under them) ──────────
  if [ "$tmpfs_tmp" = "true" ]; then
    printf -- '--tmpfs /tmp\n'
  fi

  # ── $PWD always rw ──────────────────────────────────────────────────────
  # Emitted before the user's bindings so that a later ro directive can carve a
  # read-only hole inside the working directory. Deduplicated when the config
  # binds $PWD itself.
  if ! grep -qxF -e "--bind $PWD $PWD" "$tmp_bindings" 2>/dev/null; then
    _emit_bind "--bind" "$PWD" "$PWD"
  fi

  # ── User-specified bindings, in config order ────────────────────────────
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local flag src dest
    flag="${line%% *}"
    local rest="${line#* }"
    src="${rest%% *}"
    dest="${rest#* }"
    _emit_bind "$flag" "$src" "$dest"
  done < "$tmp_bindings"
  rm -f "$tmp_bindings"

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

  # ── Namespaces and parent flags ──────────────────────────────────────────
  if [ "${WRAPIT_SANDBOX_UNSHARE_PID:-true}" = "true" ]; then
    printf -- '--unshare-pid\n'
  fi

  if [ "${WRAPIT_SANDBOX_UNSHARE_IPC:-true}" = "true" ]; then
    printf -- '--unshare-ipc\n'
  fi

  if [ "${WRAPIT_SANDBOX_UNSHARE_UTS:-true}" = "true" ]; then
    printf -- '--unshare-uts\n'
  fi

  # cgroup namespaces need a kernel new enough to have them; -try degrades
  # gracefully instead of failing the whole sandbox.
  if [ "${WRAPIT_SANDBOX_UNSHARE_CGROUP:-true}" = "true" ]; then
    printf -- '--unshare-cgroup-try\n'
  fi

  if [ "${WRAPIT_SANDBOX_DIE_WITH_PARENT:-true}" = "true" ]; then
    printf -- '--die-with-parent\n'
  fi

  # ── Always-present environment ──────────────────────────────────────────
  # These come first so that [env] pass/file/set can override them; among the
  # three, the last --setenv for a given name wins, so set beats file beats pass.
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

  _emit_env_pass
  _emit_env_file || return 1
  _emit_env_set

  printf -- '--chdir %s\n' "$PWD"
}

# _argv_push <word>
# Appends one word to the WRAPIT_BWRAP_ARGV array.
_argv_push() {
  WRAPIT_BWRAP_ARGV[${#WRAPIT_BWRAP_ARGV[@]}]="$1"
}

# load_bwrap_argv <config_file>
# Fills the global array WRAPIT_BWRAP_ARGV with the bwrap arguments for the
# given config. Runs build_bwrap_args in the current shell (via a temp file
# rather than command substitution) so the WRAPIT_* settings it parses stay
# visible to the caller.
#
# Each line of build_bwrap_args output is one flag plus its operands. Splitting
# is arity-aware and the final operand extends to the end of the line, so
# --setenv values may contain spaces. Bind source paths still may not; that
# limitation is documented in the spec.
load_bwrap_argv() {
  local config_file="$1"
  local args_file
  args_file="$(mktemp)" || return 1

  if ! build_bwrap_args "$config_file" > "$args_file"; then
    rm -f "$args_file"
    return 1
  fi

  WRAPIT_BWRAP_ARGV=()

  local line flag rest first word old_ifs
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    flag="${line%% *}"
    rest=""
    [ "$flag" != "$line" ] && rest="${line#* }"
    _argv_push "$flag"

    case "$flag" in
      # Two operands; the second runs to end of line.
      --ro-bind|--bind|--ro-bind-try|--bind-try|--setenv)
        first="${rest%% *}"
        _argv_push "$first"
        [ "$first" != "$rest" ] && _argv_push "${rest#* }"
        ;;
      # One operand, running to end of line.
      --proc|--dev|--tmpfs|--dir|--chdir|--unsetenv)
        [ -n "$rest" ] && _argv_push "$rest"
        ;;
      # No operands (--clearenv, --share-net, --unshare-*, --die-with-parent).
      --clearenv|--share-net|--unshare-*|--die-with-parent)
        ;;
      # Anything else: fall back to plain word splitting.
      *)
        if [ -n "$rest" ]; then
          old_ifs="$IFS"
          IFS=' '
          # shellcheck disable=SC2086
          set -- $rest
          IFS="$old_ifs"
          for word in "$@"; do
            [ -n "$word" ] && _argv_push "$word"
          done
        fi
        ;;
    esac
  done < "$args_file"

  rm -f "$args_file"
}
