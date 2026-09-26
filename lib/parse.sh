#!/usr/bin/env bash
# lib/parse.sh — .wrapit config file parser

# reset_wrapit_globals
# Restores every setting to its documented default. parse_wrapit calls this
# unless --keep-globals is passed, which lets several config files be parsed in
# sequence (user defaults, then the project .wrapit) with later files winning.
reset_wrapit_globals() {
  WRAPIT_NETWORK_ENABLED="true"
  WRAPIT_SANDBOX_TMPFS_TMP="true"
  WRAPIT_SANDBOX_SSH_AGENT="true"
  WRAPIT_SANDBOX_UNSHARE_PID="true"
  WRAPIT_SANDBOX_UNSHARE_IPC="true"
  WRAPIT_SANDBOX_UNSHARE_UTS="true"
  WRAPIT_SANDBOX_UNSHARE_CGROUP="true"
  WRAPIT_SANDBOX_DIE_WITH_PARENT="true"
  # [env] is deny-by-default only when clear = true; the default stays false so
  # that a hand-written .wrapit with no [env] section behaves as it always has.
  WRAPIT_ENV_CLEAR="false"
  WRAPIT_ENV_PASS=""
  WRAPIT_ENV_FILE=""
  WRAPIT_ENV_SET=""
}

reset_wrapit_globals

# _expand_path <raw_path>
# Expands ~, $HOME, $PWD, $XDG_CONFIG_HOME, $XDG_DATA_HOME, and arbitrary $VAR
_expand_path() {
  local path="$1"

  # Replace leading ~ with $HOME
  case "$path" in
    "~"/*) path="${HOME}${path#\~}" ;;
    "~")   path="$HOME" ;;
  esac

  # Default XDG vars if unset
  local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"

  # Expand $XDG_CONFIG_HOME and $XDG_DATA_HOME explicitly first
  path="${path//\$XDG_CONFIG_HOME/$xdg_config}"
  path="${path//\$XDG_DATA_HOME/$xdg_data}"

  # Expand $PWD
  path="${path//\$PWD/$PWD}"

  # Expand $HOME
  path="${path//\$HOME/$HOME}"

  # Expand remaining $VAR patterns using eval (safe: we only expand $VARNAME)
  # Replace $VARNAME (not already replaced) with their values
  local expanded
  expanded="$(printf '%s' "$path" | sed 's/\$\([A-Za-z_][A-Za-z0-9_]*\)/\${\1}/g')"
  # Use eval to expand ${VAR} patterns
  eval "expanded=\"$expanded\"" 2>/dev/null || expanded="$path"
  printf '%s' "$expanded"
}

# _trim <string>
# Prints the string with leading and trailing spaces and tabs removed.
_trim() {
  local s="$1"
  s="${s#"${s%%[! 	]*}"}"
  s="${s%"${s##*[! 	]}"}"
  printf '%s' "$s"
}

# _lower <string>
_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# parse_wrapit <config_file> [--keep-globals]
# Reads a .wrapit config file and:
#   - Prints --ro-bind / --bind lines to stdout for each binding directive
#   - Sets WRAPIT_* globals for the [network], [sandbox] and [env] sections
# Exits non-zero on parse errors.
parse_wrapit() {
  local config_file="$1"
  local keep_globals=false
  [ "${2:-}" = "--keep-globals" ] && keep_globals=true
  local lineno=0
  local current_section=""

  if [ ! -f "$config_file" ]; then
    printf 'wrapit: config file not found: %s\n' "$config_file" >&2
    return 1
  fi

  [ "$keep_globals" = "true" ] || reset_wrapit_globals

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # Strip inline comments and trim surrounding whitespace
    local stripped
    stripped="${line%%#*}"
    stripped="$(_trim "$stripped")"

    # Skip blank lines
    [ -z "$stripped" ] && continue

    # Section header: [section]
    case "$stripped" in
      "["*"]")
        current_section="${stripped#[}"
        current_section="${current_section%]}"
        # Normalise to lowercase using tr (bash 3.2 compatible)
        current_section="$(_lower "$current_section")"
        continue
        ;;
    esac

    # INI key = value inside a section
    case "$stripped" in
      *"="*)
        if [ -n "$current_section" ]; then
          local key raw_value value
          key="$(_trim "${stripped%%=*}")"
          key="$(_lower "$key")"
          # raw_value keeps its original case: environment variable names and
          # values are case-sensitive, unlike the boolean settings below.
          raw_value="$(_trim "${stripped#*=}")"
          value="$(_lower "$raw_value")"

          case "${current_section}.${key}" in
            network.enabled)          WRAPIT_NETWORK_ENABLED="$value" ;;
            sandbox.tmpfs_tmp)        WRAPIT_SANDBOX_TMPFS_TMP="$value" ;;
            sandbox.ssh_agent)        WRAPIT_SANDBOX_SSH_AGENT="$value" ;;
            sandbox.unshare_pid)      WRAPIT_SANDBOX_UNSHARE_PID="$value" ;;
            sandbox.unshare_ipc)      WRAPIT_SANDBOX_UNSHARE_IPC="$value" ;;
            sandbox.unshare_uts)      WRAPIT_SANDBOX_UNSHARE_UTS="$value" ;;
            sandbox.unshare_cgroup)   WRAPIT_SANDBOX_UNSHARE_CGROUP="$value" ;;
            sandbox.die_with_parent)  WRAPIT_SANDBOX_DIE_WITH_PARENT="$value" ;;
            env.clear)                WRAPIT_ENV_CLEAR="$value" ;;
            env.pass)
              # Accumulates across repeated keys and across merged files.
              if [ -n "$WRAPIT_ENV_PASS" ]; then
                WRAPIT_ENV_PASS="$WRAPIT_ENV_PASS $raw_value"
              else
                WRAPIT_ENV_PASS="$raw_value"
              fi
              ;;
            env.file)                 WRAPIT_ENV_FILE="$raw_value" ;;
            env.set)
              # One KEY=VALUE per line; values may contain spaces, so entries
              # are accumulated newline-separated.
              case "$raw_value" in
                *"="*) ;;
                *)
                  printf 'wrapit: line %d: [env] set expects KEY=VALUE: %s\n' \
                    "$lineno" "$raw_value" >&2
                  return 1
                  ;;
              esac
              if [ -n "$WRAPIT_ENV_SET" ]; then
                WRAPIT_ENV_SET="$WRAPIT_ENV_SET
$raw_value"
              else
                WRAPIT_ENV_SET="$raw_value"
              fi
              ;;
          esac
          continue
        fi
        ;;
    esac

    # Binding directive: <perm> <path>
    # Extract permission prefix (first word) and path (rest).
    # Trim leading whitespace from raw_path to handle multiple spaces (e.g. "ro  ~/.gitconfig").
    # Tabs are accepted as the separator, so normalise them to spaces first.
    local directive perm raw_path
    directive="$(printf '%s' "$stripped" | tr '\t' ' ')"
    perm="${directive%% *}"
    raw_path="${directive#* }"
    raw_path="$(_trim "$raw_path")"

    # Validate: if perm == stripped, there was no space (malformed)
    if [ "$perm" = "$directive" ]; then
      printf 'wrapit: line %d: malformed directive (expected "<perm> <path>"): %s\n' \
        "$lineno" "$stripped" >&2
      return 1
    fi

    # Expand the path
    local expanded_path
    expanded_path="$(_expand_path "$raw_path")"

    local optional=false
    local bwrap_flag

    case "$perm" in
      ro)
        optional=false
        bwrap_flag="--ro-bind"
        ;;
      rw)
        optional=false
        bwrap_flag="--bind"
        ;;
      "ro?")
        optional=true
        bwrap_flag="--ro-bind"
        ;;
      "rw?")
        optional=true
        bwrap_flag="--bind"
        ;;
      *)
        printf 'wrapit: line %d: unknown permission prefix "%s" (expected ro, rw, ro?, rw?)\n' \
          "$lineno" "$perm" >&2
        return 1
        ;;
    esac

    # Check path existence
    if [ ! -e "$expanded_path" ]; then
      if [ "$optional" = "true" ]; then
        continue  # silently skip
      else
        printf 'wrapit: line %d: path does not exist: %s (use ro? or rw? if optional)\n' \
          "$lineno" "$expanded_path" >&2
        return 1
      fi
    fi

    printf '%s %s %s\n' "$bwrap_flag" "$expanded_path" "$expanded_path"
  done < "$config_file"
}
