#!/usr/bin/env bats
# tests/test_check.bats — unit tests for .wrapit security checker

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/check.sh"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
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
