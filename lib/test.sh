#!/usr/bin/env bash
# lib/test.sh — --test sandbox integrity tests

# run_sandbox_tests
# Runs the 6 standard sandbox integrity tests (T1-T6), plus T7 if network is disabled.
# Requires: build_bwrap_args to be sourced, a .wrapit in $PWD or a parent.
# Prints PASS/FAIL for each test.
run_sandbox_tests() {
  local config_file="$1"
  local pass=0
  local fail=0

  _sandbox_run() {
    # Runs a command inside the sandbox, returns its exit status
    local cmd_args
    cmd_args="$(build_bwrap_args "$config_file")"

    # Build the bwrap command as an array
    local bwrap_cmd="bwrap"
    while IFS= read -r arg_line; do
      [ -z "$arg_line" ] && continue
      bwrap_cmd="$bwrap_cmd $arg_line"
    done <<EOF
$cmd_args
EOF
    eval "$bwrap_cmd" "$@" > /dev/null 2>&1
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

  # T1: Home directory hidden
  _sandbox_run bash -c 'test ! -e "$HOME/.bashrc" && test ! -e "$HOME/Documents"' 2>/dev/null
  _report T1 "Home directory hidden" $?

  # T2: Read-only paths unwritable
  _sandbox_run bash -c 'echo test >> ~/.gitconfig 2>/dev/null; [ $? -ne 0 ]' 2>/dev/null
  _report T2 "Read-only paths unwritable" $?

  # T3: Working directory writable
  _sandbox_run bash -c "touch wrapit-test-$$ && rm -f wrapit-test-$$" 2>/dev/null
  _report T3 "Working directory writable" $?

  # T4: Process isolation
  _sandbox_run bash -c 'count=$(ps aux 2>/dev/null | tail -n +2 | wc -l); [ "$count" -le 5 ]' 2>/dev/null
  _report T4 "Process namespace isolated" $?

  # T5: /tmp isolation
  local sentinel="wrapit-test-$$-sentinel"
  touch "/tmp/$sentinel" 2>/dev/null
  _sandbox_run bash -c "test ! -e /tmp/$sentinel" 2>/dev/null
  local t5_result=$?
  rm -f "/tmp/$sentinel"
  _report T5 "/tmp isolated from host" "$t5_result"

  # T6: SSH agent works, key hidden
  if [ -n "${SSH_AUTH_SOCK:-}" ] && ssh-add -l > /dev/null 2>&1; then
    _sandbox_run bash -c 'ssh-add -l > /dev/null 2>&1 && test ! -e ~/.ssh/id_ed25519 && test ! -e ~/.ssh/id_rsa' 2>/dev/null
    _report T6 "SSH agent usable, private key hidden" $?
  else
    printf 'SKIP  T6: SSH agent works, key hidden (no agent with loaded keys)\n'
  fi

  # T7: No outbound network (only if network.enabled=false)
  if [ "${WRAPIT_NETWORK_ENABLED:-true}" = "false" ]; then
    _sandbox_run bash -c 'curl -s --max-time 3 https://example.com > /dev/null 2>&1; [ $? -ne 0 ]' 2>/dev/null
    _report T7 "No outbound network" $?
  fi

  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}
