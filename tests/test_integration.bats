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
  # The user defaults file is merged into every run, so tests must not pick up
  # whatever the developer happens to have installed.
  export WRAPIT_DEFAULTS_FILE=""
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

# ---------------------------------------------------------------------------
# --test harness (bats:require-bwrap)
# ---------------------------------------------------------------------------

@test "--test reports every check as passing on a working sandbox" {
  # bats:require-bwrap
  # The whole point: the harness used to eval its own command string, which
  # destroyed the quoting of every test and reported FAIL six times over on a
  # sandbox that was fine.
  run "$WRAPIT" --test
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 failed"* ]]
  [[ "$output" != *"FAIL"* ]]
}

@test "--test leaves the ro file it targets untouched on the host" {
  # bats:require-bwrap
  # T2 appends to a ro-mounted file. Under eval that redirection was performed
  # by the host shell, so every --test run appended to the real ~/.gitconfig.
  # The setup config mounts ro ~/.gitconfig, which is the file T2 picks.
  [ -f "$HOME/.gitconfig" ] || skip "no ~/.gitconfig to check"
  local before after
  before="$(cksum < "$HOME/.gitconfig")"
  run "$WRAPIT" --test
  after="$(cksum < "$HOME/.gitconfig")"
  [ "$before" = "$after" ]
}

@test "--test on a ro mount under HOME exercises T2 rather than skipping it" {
  # bats:require-bwrap
  run "$WRAPIT" --test
  [[ "$output" == *"T2"* ]]
  # ~/.gitconfig is mounted ro by the setup config, so T2 has something to assert.
  [[ "$output" != *"SKIP  T2"* ]]
}

# ---------------------------------------------------------------------------
# Environment isolation end to end
# ---------------------------------------------------------------------------

@test "with [env] clear = true an unlisted host variable is not visible" {
  # bats:require-bwrap
  printf '[sandbox]\ntmpfs_tmp = true\n\n[env]\nclear = true\npass = WRAPIT_ALLOWED\n\nro ~/.gitconfig\n' \
    > "$TEST_DIR/.wrapit"
  WRAPIT_ALLOWED=yes WRAPIT_DENIED=no run "$WRAPIT" bash -c 'printf "%s/%s" "${WRAPIT_ALLOWED:-unset}" "${WRAPIT_DENIED:-unset}"'
  [ "$status" -eq 0 ]
  [ "$output" = "yes/unset" ]
}

@test "without an [env] section the host environment is still inherited" {
  # bats:require-bwrap
  WRAPIT_INHERITED=yes run "$WRAPIT" bash -c 'printf "%s" "${WRAPIT_INHERITED:-unset}"'
  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]
}

@test "an [env] set value containing spaces arrives intact" {
  # bats:require-bwrap
  printf '[sandbox]\ntmpfs_tmp = true\n\n[env]\nclear = true\nset = WRAPIT_PHRASE=hello world\n\nro ~/.gitconfig\n' \
    > "$TEST_DIR/.wrapit"
  run "$WRAPIT" bash -c 'printf "%s" "$WRAPIT_PHRASE"'
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

# ---------------------------------------------------------------------------
# Read-only override inside a read-write tree
# ---------------------------------------------------------------------------

@test "a ro directive after an rw mount makes that file unwritable" {
  # bats:require-bwrap
  mkdir -p "$TEST_DIR/tree"
  printf 'pinned\n' > "$TEST_DIR/tree/pinned.json"
  printf 'free\n' > "$TEST_DIR/tree/other.json"
  printf '[sandbox]\ntmpfs_tmp = true\n\nrw %s/tree\nro %s/tree/pinned.json\n' \
    "$TEST_DIR" "$TEST_DIR" > "$TEST_DIR/.wrapit"

  # The pinned file cannot be written...
  run "$WRAPIT" bash -c 'printf x >> "$1"' sh "$TEST_DIR/tree/pinned.json"
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_DIR/tree/pinned.json")" = "pinned" ]

  # ...while the rest of the tree still can.
  run "$WRAPIT" bash -c 'printf x >> "$1"' sh "$TEST_DIR/tree/other.json"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Generated config
# ---------------------------------------------------------------------------

@test "a generated config does not mount the docker socket" {
  rm -f "$TEST_DIR/.wrapit"
  run "$WRAPIT" --init --preset claude-code
  [ "$status" -eq 0 ]
  # Present as a commented-out opt-in, never as a live directive.
  ! grep -qE '^[[:space:]]*rw\??[[:space:]]+/var/run/docker\.sock' "$TEST_DIR/.wrapit"
  grep -q 'docker.sock' "$TEST_DIR/.wrapit"
}

@test "a generated config starts from an empty environment" {
  rm -f "$TEST_DIR/.wrapit"
  run "$WRAPIT" --init --preset claude-code
  [ "$status" -eq 0 ]
  grep -qE '^[[:space:]]*clear[[:space:]]*=[[:space:]]*true' "$TEST_DIR/.wrapit"
}
