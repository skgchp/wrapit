#!/usr/bin/env bats
# tests/test_check.bats — unit tests for .wrapit security checker

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/check.sh"
  TEST_DIR="$(mktemp -d)"
  # The user defaults file is merged into every run, so tests must not pick up
  # whatever the developer happens to have installed.
  export WRAPIT_DEFAULTS_FILE=""
  # The sensitive-path list resolves ~/.config via XDG_CONFIG_HOME; pin it so the
  # developer's own setting cannot change what these tests assert.
  unset XDG_CONFIG_HOME
}

teardown() {
  rm -rf "$TEST_DIR"
}

# check_wrapit_with_home <dir> <directive>...
# Writes the given directives to <dir>/.wrapit with the literal word HOME
# replaced by $HOME, then checks it. Keeps the sensitive-path list, which is
# built from $HOME, aligned with what the config names.
check_wrapit_with_home() {
  local dir="$1"; shift
  local d
  : > "$dir/.wrapit"
  for d in "$@"; do
    printf '%s\n' "${d//HOME/$HOME}" >> "$dir/.wrapit"
  done
  check_wrapit "$dir/.wrapit"
}

# ---------------------------------------------------------------------------
# Errors — must exit 1 and block execution
# ---------------------------------------------------------------------------

@test "rw / is a blocking error" {
  printf 'rw /\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /etc is a blocking error" {
  printf 'rw /etc\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /usr is a blocking error" {
  printf 'rw /usr\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /bin is a blocking error" {
  printf 'rw /bin\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /lib is a blocking error" {
  printf 'rw /lib\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /lib64 is a blocking error" {
  printf 'rw /lib64\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "rw /home is a blocking error" {
  printf 'rw /home\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
}

@test "error output includes the dangerous path" {
  printf 'rw /etc\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/etc"* ]]
}

# ---------------------------------------------------------------------------
# Warnings — exit 0 with warning text in output
# ---------------------------------------------------------------------------

@test "rw ~/.ssh produces a warning" {
  printf 'rw %s/.ssh\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "rw ~/.aws produces a warning" {
  printf 'rw %s/.aws\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "rw ~/.azure produces a warning" {
  printf 'rw %s/.azure\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "rw ~/.config/gcloud produces a warning" {
  printf 'rw %s/.config/gcloud\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "rw ~/.gnupg produces a warning" {
  printf 'rw %s/.gnupg\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test ".env file binding produces a warning" {
  printf 'rw %s/.env\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "docker socket binding produces a warning" {
  printf 'rw /var/run/docker.sock\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "SSH private key path produces a warning" {
  printf 'ro %s/.ssh/id_ed25519\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "SSH RSA key path produces a warning" {
  printf 'ro %s/.ssh/id_rsa\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "network=false with cloud credentials rw produces inconsistency warning" {
  printf '[network]\nenabled = false\nrw %s/.aws\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  # Should warn about both the cloud creds and the inconsistency
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

# ---------------------------------------------------------------------------
# Clean config — no warnings, exit 0
# ---------------------------------------------------------------------------

@test "clean config exits 0 with no output" {
  # minimal.wrapit has no dangerous patterns; use a safe temp config
  printf 'ro %s\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# --force flag
# ---------------------------------------------------------------------------

@test "--force allows warnings but still shows them" {
  printf 'rw %s/.ssh\n' "$HOME" > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit" --force
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}

@test "--force does not bypass blocking errors" {
  printf 'rw /\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit" --force
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Sandbox-escape paths
# ---------------------------------------------------------------------------

@test "docker socket is labelled a sandbox-escape path" {
  printf 'rw /var/run/docker.sock\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SANDBOX ESCAPE PATH"* ]]
}

@test "a read-only docker socket is flagged too" {
  # A ro bind is no defence: the socket is still there to be spoken to.
  printf 'ro /run/docker.sock\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SANDBOX ESCAPE PATH"* ]]
}

@test "podman socket is flagged as an escape path" {
  printf 'rw /run/podman/podman.sock\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SANDBOX ESCAPE PATH"* ]]
}

@test "an escape path is a warning, not a blocking error" {
  printf 'rw /var/run/docker.sock\n' > "$TEST_DIR/.wrapit"
  run check_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Writable agent config inside an rw mount
# ---------------------------------------------------------------------------

@test "rw mount covering a sensitive agent config warns" {
  HOME="$TEST_DIR/home" run check_wrapit_with_home "$TEST_DIR" 'rw HOME/.pi'
  [ "$status" -eq 0 ]
  [[ "$output" == *"models.json is writable"* ]]
}

@test "a later ro directive silences the warning" {
  HOME="$TEST_DIR/home" run check_wrapit_with_home "$TEST_DIR" \
    'rw HOME/.pi' 'ro HOME/.pi/agent/models.json' 'ro HOME/.pi/agent/web-search.json'
  [ "$status" -eq 0 ]
  [[ "$output" != *"models.json is writable"* ]]
}

@test "a ro directive placed before the rw mount does not silence it" {
  # bwrap applies mounts in order, so the rw mount would win here.
  HOME="$TEST_DIR/home" run check_wrapit_with_home "$TEST_DIR" \
    'ro HOME/.pi/agent/models.json' 'rw HOME/.pi'
  [ "$status" -eq 0 ]
  [[ "$output" == *"models.json is writable"* ]]
}

@test "rw mount covering the user defaults file warns" {
  HOME="$TEST_DIR/home" run check_wrapit_with_home "$TEST_DIR" 'rw HOME/.config/wrapit'
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaults.wrapit is writable"* ]]
}

@test "a config that touches none of those files stays silent" {
  HOME="$TEST_DIR/home" run check_wrapit_with_home "$TEST_DIR" 'rw HOME/.npm'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
