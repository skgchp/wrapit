#!/usr/bin/env bash
# lib/parse.sh — .wrapit config file parser

# Default section globals (overwritten by parse_wrapit)
WRAPIT_NETWORK_ENABLED="true"
WRAPIT_SANDBOX_TMPFS_TMP="true"
WRAPIT_SANDBOX_SSH_AGENT="true"
WRAPIT_SANDBOX_UNSHARE_PID="true"
WRAPIT_SANDBOX_DIE_WITH_PARENT="true"

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

# parse_wrapit <config_file>
# Reads a .wrapit config file and:
#   - Prints --ro-bind / --bind lines to stdout for each binding directive
#   - Sets WRAPIT_* globals for [network] and [sandbox] sections
# Exits non-zero on parse errors.
parse_wrapit() {
  local config_file="$1"
  local lineno=0
  local current_section=""

  if [ ! -f "$config_file" ]; then
    printf 'wrapit: config file not found: %s\n' "$config_file" >&2
    return 1
  fi

  # Reset globals to defaults before parsing
  WRAPIT_NETWORK_ENABLED="true"
  WRAPIT_SANDBOX_TMPFS_TMP="true"
  WRAPIT_SANDBOX_SSH_AGENT="true"
  WRAPIT_SANDBOX_UNSHARE_PID="true"
  WRAPIT_SANDBOX_DIE_WITH_PARENT="true"

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # Strip inline comments and trim trailing whitespace
    local stripped
    stripped="${line%%#*}"
    # Trim leading whitespace
    stripped="${stripped#"${stripped%%[! ]*}"}"
    # Trim trailing whitespace
    stripped="${stripped%"${stripped##*[! ]}"}"

    # Skip blank lines
    [ -z "$stripped" ] && continue

    # Section header: [section]
    case "$stripped" in
      "["*"]")
        current_section="${stripped#[}"
        current_section="${current_section%]}"
        # Normalise to lowercase using tr (bash 3.2 compatible)
        current_section="$(printf '%s' "$current_section" | tr '[:upper:]' '[:lower:]')"
        continue
        ;;
    esac

    # INI key = value inside a section
    case "$stripped" in
      *"="*)
        if [ -n "$current_section" ]; then
          local key value
          key="${stripped%%=*}"
          value="${stripped#*=}"
          # Trim whitespace from key and value
          key="${key%"${key##*[! ]}"}"
          key="${key#"${key%%[! ]*}"}"
          value="${value%"${value##*[! ]}"}"
          value="${value#"${value%%[! ]*}"}"
          key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
          value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

          case "${current_section}.${key}" in
            network.enabled)         WRAPIT_NETWORK_ENABLED="$value" ;;
            sandbox.tmpfs_tmp)       WRAPIT_SANDBOX_TMPFS_TMP="$value" ;;
            sandbox.ssh_agent)       WRAPIT_SANDBOX_SSH_AGENT="$value" ;;
            sandbox.unshare_pid)     WRAPIT_SANDBOX_UNSHARE_PID="$value" ;;
            sandbox.die_with_parent) WRAPIT_SANDBOX_DIE_WITH_PARENT="$value" ;;
          esac
          continue
        fi
        ;;
    esac

    # Binding directive: <perm> <path>
    # Extract permission prefix (first word) and path (rest).
    # Trim leading whitespace from raw_path to handle multiple spaces (e.g. "ro  ~/.gitconfig").
    local perm raw_path
    perm="${stripped%% *}"
    raw_path="${stripped#* }"
    raw_path="${raw_path#"${raw_path%%[! ]*}"}"

    # Validate: if perm == stripped, there was no space (malformed)
    if [ "$perm" = "$stripped" ]; then
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
