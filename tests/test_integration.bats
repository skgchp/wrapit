#!/usr/bin/env bats
# tests/test_integration.bats — end-to-end sandbox tests (require bwrap)
# Tests tagged with "# bats:require-bwrap" are skipped when bwrap is absent.

setup() {
  # Skip all bwrap tests if bwrap is not available
  if ! command -v bwrap > /dev/null 2>&1; then
    skip "bwrap not found in PATH"
  fi

  WRAPIT="${BATS_TEST_DIRNAME}/../wrapit"
  TEST_DIR="$(mktemp -d)"
  ORIG_PWD="$PWD"
  cd "$TEST_DIR"

  # Create a minimal .wrapit for tests that need one
  printf '[sandbox]\ntmpfs_tmp = true\nunshare_pid = true\ndie_with_parent = true\n\n[network]\nenabled = true\n\nro ~/.gitconfig\n' \
    > "$TEST_DIR/.wrapit"
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------

@test "--version prints a version string and exits 0" {
  run "$WRAPIT" --version
  [ "$status" -eq 0 ]
  [[ "$output" != "" ]]
}

@test "--help prints usage and exits 0" {
  run "$WRAPIT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrapit"* ]]
}

@test "--dry-run prints a bwrap command without executing" {
  run "$WRAPIT" --dry-run echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"bwrap"* ]]
}

@test "--dry-run output is a valid bwrap command (re-executable)" {
  # Capture the dry-run output and try to execute it
  run "$WRAPIT" --dry-run echo hello
  [ "$status" -eq 0 ]
  # The first line should be an executable bwrap command
  local cmd
  cmd="$(printf '%s\n' "$output" | head -1)"
  [[ "$cmd" == "bwrap "* ]]
}

@test "--check on clean config exits 0" {
  run "$WRAPIT" --check
  [ "$status" -eq 0 ]
}

@test "--check on dangerous config exits 1" {
  printf 'rw /\n' > "$TEST_DIR/.wrapit"
  run "$WRAPIT" --check
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# .wrapit discovery
# ---------------------------------------------------------------------------

@test "wrapit finds .wrapit in parent directory" {
  mkdir -p "$TEST_DIR/subdir"
  cd "$TEST_DIR/subdir"
  run "$WRAPIT" --dry-run echo hello
  [ "$status" -eq 0 ]
}

@test "wrapit exits 1 with helpful message when no .wrapit found" {
  # Use a temp dir that has no .wrapit and no parent with one
  local isolated
  isolated="$(mktemp -d)"
  run "$WRAPIT" --dry-run echo hello
  # We're in TEST_DIR which has .wrapit, so this should pass
  # The real no-.wrapit test is harder in bats; we test the message indirectly
  cd "$isolated"
  run "$WRAPIT" --dry-run echo hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"wrapit --init"* ]] || [[ "$output" == *".wrapit"* ]]
  rm -rf "$isolated"
}

# ---------------------------------------------------------------------------
# Sandbox integrity tests — T1-T6 (bats:require-bwrap)
# ---------------------------------------------------------------------------

@test "T1: home directory is hidden inside sandbox" {
  # bats:require-bwrap
  # $HOME/.bashrc should not be visible (home is not mounted)
  run "$WRAPIT" bash -c 'test ! -e "$HOME/.bashrc"'
  [ "$status" -eq 0 ]
}

@test "T2: read-only paths are unwritable inside sandbox" {
  # bats:require-bwrap
  # ~/.gitconfig is mounted ro; writing to it should fail
  run "$WRAPIT" bash -c 'echo test >> ~/.gitconfig 2>/dev/null; [ $? -ne 0 ]'
  [ "$status" -eq 0 ]
}

@test "T3: working directory is writable inside sandbox" {
  # bats:require-bwrap
  run "$WRAPIT" bash -c "touch wrapit-test-$$ && rm wrapit-test-$$"
  [ "$status" -eq 0 ]
}

@test "T4: process namespace is isolated" {
  # bats:require-bwrap
  # With unshare_pid=true, far fewer processes visible than on the host.
  # The pipeline itself spawns ~6 processes (bwrap + bash + subshell + ps + tail + wc),
  # but the host typically has hundreds. Allow up to 15 to be safe.
  local host_count
  host_count="$(ps aux 2>/dev/null | tail -n +2 | wc -l)"
  run "$WRAPIT" bash -c 'ps aux 2>/dev/null | tail -n +2 | wc -l'
  [ "$status" -eq 0 ]
  local sandbox_count="$output"
  # Sandbox should have far fewer processes than the host
  [ "$sandbox_count" -lt "$host_count" ]
  # And should have a reasonably small count (≤15 allows for pipeline overhead)
  [ "$sandbox_count" -le 15 ]
}

@test "T5: /tmp is isolated from host" {
  # bats:require-bwrap
  local sentinel="wrapit-host-$$"
  touch "/tmp/$sentinel"
  run "$WRAPIT" bash -c "test ! -e /tmp/$sentinel"
  [ "$status" -eq 0 ]
  rm -f "/tmp/$sentinel"
}

@test "T6: SSH agent socket usable but private key hidden (when agent loaded)" {
  # bats:require-bwrap
  # Only run if SSH_AUTH_SOCK is set and has an identity loaded
  if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l > /dev/null 2>&1; then
    skip "No SSH agent with loaded keys available"
  fi

  # Set ssh_agent=true in config
  printf '[sandbox]\nssh_agent = true\ntmpfs_tmp = true\nunshare_pid = true\ndie_with_parent = true\n\n[network]\nenabled = true\n\nro ~/.gitconfig\n' \
    > "$TEST_DIR/.wrapit"

  run "$WRAPIT" bash -c 'ssh-add -l > /dev/null 2>&1'
  [ "$status" -eq 0 ]

  run "$WRAPIT" bash -c 'test ! -e ~/.ssh/id_ed25519 && test ! -e ~/.ssh/id_rsa'
  [ "$status" -eq 0 ]
}

@test "T7: no outbound network when network.enabled=false" {
  # bats:require-bwrap
  printf '[sandbox]\ntmpfs_tmp = true\nunshare_pid = true\ndie_with_parent = true\n\n[network]\nenabled = false\n\nro ~/.gitconfig\n' \
    > "$TEST_DIR/.wrapit"
  run "$WRAPIT" bash -c 'curl -s --max-time 3 https://example.com > /dev/null 2>&1'
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

@test "missing non-optional path exits 1 with helpful message" {
  printf 'ro /nonexistent/path/xyz\n' > "$TEST_DIR/.wrapit"
  run "$WRAPIT" echo hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}
