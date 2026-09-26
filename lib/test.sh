#!/usr/bin/env bash
# lib/test.sh — --test sandbox integrity tests

# _first_ro_file_in_home
# Prints the first --ro-bind source in the built argv that is a regular file
# under $HOME — a path the sandbox is supposed to expose read-only. Returns 1
# when the config mounts no such file, in which case T2 has nothing to assert.
_first_ro_file_in_home() {
  local i=0
  local n=${#WRAPIT_BWRAP_ARGV[@]}
  local src
  while [ "$i" -lt "$n" ]; do
    if [ "${WRAPIT_BWRAP_ARGV[$i]}" = "--ro-bind" ]; then
      src="${WRAPIT_BWRAP_ARGV[$((i + 1))]}"
      case "$src" in
        "$HOME"/*)
          if [ -f "$src" ]; then
            printf '%s' "$src"
            return 0
          fi
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}

# run_sandbox_tests <config_file>
# Runs the 6 standard sandbox integrity tests (T1-T6), plus T7 if network is
# disabled. Prints PASS/FAIL/SKIP for each test; returns non-zero if any failed.
run_sandbox_tests() {
  local config_file="$1"
  local pass=0
  local fail=0
  local skip=0

  # Build the argv once, in this shell. Two reasons this is not done per test:
  # the WRAPIT_* settings parsed from the config stay visible below (T7 needs
  # WRAPIT_NETWORK_ENABLED), and there is no command string to be re-parsed.
  load_bwrap_argv "$config_file" || return 1

  # Runs a command inside the sandbox and returns its exit status.
  # "$@" must stay quoted: the test commands below rely on their own quoting
  # surviving, which is exactly what an eval here would destroy.
  _sandbox_run() {
    bwrap "${WRAPIT_BWRAP_ARGV[@]}" "$@" > /dev/null 2>&1
  }

  _report() {
    local test_id="$1"
    local desc="$2"
    local result="$3"  # 0 = pass
    if [ "$result" -eq 0 ]; then
      printf 'PASS  %s: %s\n' "$test_id" "$desc"
      pass=$((pass + 1))
    else
      printf 'FAIL  %s: %s\n' "$test_id" "$desc"
      fail=$((fail + 1))
    fi
  }

  _skip() {
    printf 'SKIP  %s: %s (%s)\n' "$1" "$2" "$3"
    skip=$((skip + 1))
  }

  printf 'Testing sandbox defined by %s\n\n' "$config_file"

  # T1: Home directory hidden
  _sandbox_run bash -c 'test ! -e "$HOME/.bashrc" && test ! -e "$HOME/Documents"'
  _report T1 "Home directory hidden" $?

  # T2: Read-only paths unwritable. The path is taken from the config rather
  # than hardcoded, and passed as $1 so no quoting of it is needed.
  local ro_file
  if ro_file="$(_first_ro_file_in_home)"; then
    _sandbox_run bash -c 'printf x >> "$1" 2>/dev/null; [ $? -ne 0 ]' sh "$ro_file"
    _report T2 "Read-only paths unwritable ($ro_file)" $?
  else
    _skip T2 "Read-only paths unwritable" "config mounts no ro file under \$HOME"
  fi

  # T3: Working directory writable
  _sandbox_run bash -c 'touch "$1" && rm -f "$1"' sh "wrapit-test-$$"
  _report T3 "Working directory writable" $?

  # T4: Process isolation. The pipeline itself accounts for a handful of
  # processes, so the bound is generous; the host has hundreds.
  _sandbox_run bash -c 'count=$(ps aux 2>/dev/null | tail -n +2 | wc -l); [ "$count" -le 15 ]'
  _report T4 "Process namespace isolated" $?

  # T5: /tmp isolation
  local sentinel="/tmp/wrapit-test-$$-sentinel"
  touch "$sentinel" 2>/dev/null
  _sandbox_run bash -c 'test ! -e "$1"' sh "$sentinel"
  local t5_result=$?
  rm -f "$sentinel"
  _report T5 "/tmp isolated from host" "$t5_result"

  # T6: SSH agent works, key hidden
  if [ -n "${SSH_AUTH_SOCK:-}" ] && ssh-add -l > /dev/null 2>&1; then
    _sandbox_run bash -c 'ssh-add -l > /dev/null 2>&1 && test ! -e ~/.ssh/id_ed25519 && test ! -e ~/.ssh/id_rsa'
    _report T6 "SSH agent usable, private key hidden" $?
  else
    _skip T6 "SSH agent usable, private key hidden" "no agent with loaded keys"
  fi

  # T7: No outbound network (only if network.enabled=false)
  if [ "${WRAPIT_NETWORK_ENABLED:-true}" = "false" ]; then
    _sandbox_run bash -c 'curl -s --max-time 3 https://example.com > /dev/null 2>&1; [ $? -ne 0 ]'
    _report T7 "No outbound network" $?
  fi

  if [ "$skip" -gt 0 ]; then
    printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
  else
    printf '\n%d passed, %d failed\n' "$pass" "$fail"
  fi
  [ "$fail" -eq 0 ]
}
