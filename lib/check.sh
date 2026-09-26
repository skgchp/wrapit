#!/usr/bin/env bash
# lib/check.sh — .wrapit security scanner

# _sensitive_files
# Prints one absolute path per line for files that an agent must not be able to
# rewrite, because doing so lets it widen its own policy on the next run.
# Extend this list as new harnesses grow config of this kind.
_sensitive_files() {
  # pi: these decide which inference endpoint the agent talks to and which
  # hosts it may fetch, so write access lets it repoint both from inside.
  printf '%s|%s\n' "$HOME/.pi/agent/models.json" "the agent could repoint its own model endpoint"
  printf '%s|%s\n' "$HOME/.pi/agent/web-search.json" "the agent could widen its own fetch allow-list"
  # wrapit's own defaults are merged into every project, so write access here
  # lets the agent grant itself more of the filesystem next run.
  printf '%s|%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/wrapit/defaults.wrapit" \
    "the agent could grant itself wider access on the next run"
}

# _escape_path_reason <path>
# Prints why the path is a sandbox-escape vector, or nothing if it is not one.
_escape_path_reason() {
  case "$1" in
    */docker.sock|*/docker.sock/)
      printf 'the Docker socket grants trivial root on the host: anything with it can start a privileged container that mounts /'
      ;;
    */podman.sock|*/podman.sock/)
      printf 'the Podman socket lets the agent start containers outside the sandbox'
      ;;
    /var/run/docker|/run/docker)
      printf 'the Docker runtime directory contains the socket, which grants trivial root on the host'
      ;;
  esac
}

# _covering_directive <target_path> <directives_file>
# Prints "perm|lineno" for the LAST directive whose mount covers target_path, or
# nothing when no directive covers it. Last wins because bwrap applies mounts in
# order, so a later ro directive genuinely overrides an earlier rw one.
_covering_directive() {
  local target="$1"
  local file="$2"
  local last=""
  local lineno perm path
  while IFS='|' read -r lineno perm path; do
    [ -n "$path" ] || continue
    case "$target" in
      "$path"|"$path"/*) last="$perm|$lineno" ;;
    esac
  done < "$file"
  printf '%s' "$last"
}

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

  # Collected directives, one "lineno|perm|expanded_path" per line. The scan
  # needs two passes: whether an rw mount is a problem depends on whether a
  # LATER directive covers the same path read-only.
  local directives
  directives="$(mktemp)" || return 1

  local lineno=0
  local current_section=""

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    lineno=$((lineno + 1))

    # Strip comments and trim
    local line
    line="${raw_line%%#*}"
    line="$(_trim "$line")"
    [ -z "$line" ] && continue

    # Section header
    case "$line" in
      "["*"]")
        current_section="${line#[}"
        current_section="${current_section%]}"
        current_section="$(_lower "$current_section")"
        continue
        ;;
    esac

    # INI key=value inside section — track network.enabled
    case "$line" in
      *"="*)
        if [ -n "$current_section" ]; then
          local key val
          key="$(_lower "$(_trim "${line%%=*}")")"
          val="$(_lower "$(_trim "${line#*=}")")"
          case "${current_section}.${key}" in
            network.enabled) _CHECK_NETWORK_ENABLED="$val" ;;
          esac
          continue
        fi
        ;;
    esac

    # Binding directive
    local directive perm path_raw
    directive="$(printf '%s' "$line" | tr '\t' ' ')"
    perm="${directive%% *}"
    path_raw="$(_trim "${directive#* }")"
    [ "$perm" = "$directive" ] && continue  # malformed, skip (parse.sh handles errors)

    # Expand path for matching
    local path_exp
    path_exp="$(_expand_path "$path_raw")"

    printf '%s|%s|%s\n' "$lineno" "$perm" "$path_exp" >> "$directives"

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

    # ── Sandbox-escape paths ────────────────────────────────────────────────
    # Called out separately from ordinary warnings: these do not widen the
    # sandbox, they end it. A read-only bind is no defence — the socket is
    # still there to be spoken to.
    local escape_reason
    escape_reason="$(_escape_path_reason "$path_exp")"
    if [ -n "$escape_reason" ]; then
      printf 'warning: SANDBOX ESCAPE PATH — %s (line %d): %s\n' \
        "$path_exp" "$lineno" "$escape_reason"
      warnings=$((warnings + 1))
      continue
    fi

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

  # ── Second pass: writable agent config inside an rw mount ─────────────────
  # A directory mounted rw may contain a file the agent should not be able to
  # rewrite. A later ro directive covering that file fixes it, which is why
  # this cannot be decided while streaming the file.
  local sensitive reason cover cover_perm cover_line
  while IFS='|' read -r sensitive reason; do
    [ -n "$sensitive" ] || continue
    # Deliberately not gated on the file existing: an agent that can write the
    # directory can create the file, which has the same effect.
    cover="$(_covering_directive "$sensitive" "$directives")"
    [ -n "$cover" ] || continue
    cover_perm="${cover%%|*}"
    cover_line="${cover#*|}"
    case "$cover_perm" in
      rw|"rw?")
        printf 'warning: %s is writable via the rw mount on line %d — %s\n' \
          "$sensitive" "$cover_line" "$reason"
        printf '         add "ro %s" after that line to pin it read-only\n' "$sensitive"
        warnings=$((warnings + 1))
        ;;
    esac
  done <<EOF
$(_sensitive_files)
EOF

  rm -f "$directives"

  # Return status
  if [ "$errors" -gt 0 ]; then
    return 1
  fi
  return 0
}
