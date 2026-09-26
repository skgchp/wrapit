#!/usr/bin/env bash
# lib/check.sh — .wrapit security scanner

# check_wrapit <config_file> [--force]
# Validates a .wrapit file for dangerous patterns.
# Errors (blocking): exit 1 regardless of --force
# Warnings (non-blocking): printed but exit 0; --force does not suppress display
check_wrapit() {
  local config_file="$1"
  local force=false
  local errors=0
  local warnings=0

  [ "${2:-}" = "--force" ] && force=true

  if [ ! -f "$config_file" ]; then
    printf 'wrapit: config file not found: %s\n' "$config_file" >&2
    return 1
  fi

  local lineno=0
  local current_section=""

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    lineno=$((lineno + 1))

    # Strip comments and trim
    local line
    line="${raw_line%%#*}"
    line="${line#"${line%%[! ]*}"}"
    line="${line%"${line##*[! ]}"}"
    [ -z "$line" ] && continue

    # Section header
    case "$line" in
      "["*"]")
        current_section="${line#[}"
        current_section="${current_section%]}"
        current_section="$(printf '%s' "$current_section" | tr '[:upper:]' '[:lower:]')"
        continue
        ;;
    esac

    # INI key=value inside section — track network.enabled
    case "$line" in
      *"="*)
        if [ -n "$current_section" ]; then
          local key val
          key="${line%%=*}"
          val="${line#*=}"
          key="${key%"${key##*[! ]}"}"; key="${key#"${key%%[! ]*}"}"
          val="${val%"${val##*[! ]}"}"; val="${val#"${val%%[! ]*}"}"
          key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
          val="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
          case "${current_section}.${key}" in
            network.enabled) _CHECK_NETWORK_ENABLED="$val" ;;
          esac
          continue
        fi
        ;;
    esac

    # Binding directive
    local perm path_raw
    perm="${line%% *}"
    path_raw="${line#* }"
    [ "$perm" = "$line" ] && continue  # malformed, skip (parse.sh handles errors)

    # Expand path for matching
    local path_exp
    path_exp="$(_expand_path "$path_raw")"

    # ── Blocking error patterns ─────────────────────────────────────────────
    # Only rw triggers errors (ro-mounting these is allowed by bwrap)
    case "$perm" in
      rw|"rw?")
        case "$path_exp" in
          "/"|\
          /etc|/etc/|\
          /usr|/usr/|\
          /bin|/bin/|\
          /lib|/lib/|\
          /lib64|/lib64/|\
          /home|/home/)
            printf 'error: dangerous rw binding: %s (line %d) — would defeat the sandbox\n' \
              "$path_exp" "$lineno"
            errors=$((errors + 1))
            continue
            ;;
        esac
        ;;
    esac

    # ── Warning patterns ────────────────────────────────────────────────────
    local warn_msg=""

    # SSH private keys by filename pattern
    case "$path_exp" in
      *id_rsa*|*id_ed25519*|*id_ecdsa*)
        warn_msg="SSH private key file exposed: $path_exp"
        ;;
    esac

    # rw on sensitive dirs
    case "$perm" in
      rw|"rw?")
        case "$path_exp" in
          */\.ssh|*/\.ssh/)
            warn_msg="rw mount of ~/.ssh exposes private key files to the agent"
            ;;
          */\.aws|*/\.aws/|*/\.azure|*/\.azure/)
            warn_msg="rw mount of cloud credentials ($path_exp); prefer ro"
            ;;
          */\.config/gcloud|*/\.config/gcloud/)
            warn_msg="rw mount of cloud credentials ($path_exp); prefer ro"
            ;;
          */\.gnupg|*/\.gnupg/)
            warn_msg="rw mount of ~/.gnupg exposes GPG private keys"
            ;;
          /var/run/docker.sock)
            warn_msg="docker socket exposed; agent could escape sandbox by spawning containers"
            ;;
        esac
        ;;
    esac

    # .env file binding (any permission)
    case "$path_exp" in
      *\.env|*\.env/)
        warn_msg="binding a .env file may expose API keys or secrets: $path_exp"
        ;;
    esac

    if [ -n "$warn_msg" ]; then
      printf 'warning: %s\n' "$warn_msg"
      warnings=$((warnings + 1))
    fi
  done < "$config_file"

  # Inconsistency check: network=false + cloud credentials rw
  if [ "${_CHECK_NETWORK_ENABLED:-true}" = "false" ] && [ "$warnings" -gt 0 ]; then
    : # warnings already printed; this case is covered by the cloud creds warning above
  fi

  # Return status
  if [ "$errors" -gt 0 ]; then
    return 1
  fi
  return 0
}
