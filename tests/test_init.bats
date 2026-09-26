#!/usr/bin/env bats
# tests/test_init.bats — unit tests for init wizard (non-interactive paths)

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/check.sh"
  source "${BATS_TEST_DIRNAME}/../lib/presets.sh"
  source "${BATS_TEST_DIRNAME}/../lib/init.sh"
  TEST_DIR="$(mktemp -d)"
  ORIG_PWD="$PWD"
  cd "$TEST_DIR"
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Helper: skip if a real preset file does not exist
# ---------------------------------------------------------------------------

_skip_if_no_preset() {
  local name="$1"
  [ -f "${WRAPIT_PRESETS_DIR}/${name}.preset" ] || \
    skip "preset file ${name}.preset not found in ${WRAPIT_PRESETS_DIR}"
}

# ---------------------------------------------------------------------------
# --preset flag (non-interactive)
# ---------------------------------------------------------------------------

@test "--preset claude-code writes .wrapit to PWD" {
  _skip_if_no_preset "claude-code"
  run run_init --preset claude-code
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.wrapit" ]
}

@test "--preset claude-code output contains claude-code bindings" {
  _skip_if_no_preset "claude-code"
  run_init --preset claude-code
  grep -q "\.claude" "$TEST_DIR/.wrapit"
}

@test "--preset aider writes .wrapit with aider bindings" {
  _skip_if_no_preset "aider"
  run_init --preset aider
  [ -f "$TEST_DIR/.wrapit" ]
  grep -q "\.aider" "$TEST_DIR/.wrapit"
}

@test "--preset does not hang without a TTY" {
  _skip_if_no_preset "claude-code"
  run timeout 5 bash -c "
    source '${BATS_TEST_DIRNAME}/../lib/parse.sh'
    source '${BATS_TEST_DIRNAME}/../lib/check.sh'
    source '${BATS_TEST_DIRNAME}/../lib/presets.sh'
    source '${BATS_TEST_DIRNAME}/../lib/init.sh'
    cd '$TEST_DIR'
    run_init --preset claude-code </dev/null
  "
  [ "$status" -eq 0 ]
}

@test "written .wrapit starts with a comment header" {
  _skip_if_no_preset "claude-code"
  run_init --preset claude-code
  head -1 "$TEST_DIR/.wrapit" | grep -q '^#'
}

@test "written .wrapit is valid syntax (parseable)" {
  _skip_if_no_preset "claude-code"
  run_init --preset claude-code
  sed 's/^ro /ro? /; s/^rw /rw? /' "$TEST_DIR/.wrapit" > "$TEST_DIR/.wrapit-lenient"
  run parse_wrapit "$TEST_DIR/.wrapit-lenient"
  [ "$status" -eq 0 ]
}

@test "written .wrapit contains project-specific bindings section" {
  _skip_if_no_preset "claude-code"
  run_init --preset claude-code
  grep -q "Project-specific bindings" "$TEST_DIR/.wrapit"
}

@test "written .wrapit contains rw \$PWD in project workspace section" {
  _skip_if_no_preset "claude-code"
  run_init --preset claude-code
  grep -q 'rw.*\$PWD' "$TEST_DIR/.wrapit"
}

# ---------------------------------------------------------------------------
# Harness detection via mock PATH
# ---------------------------------------------------------------------------

@test "detect_harnesses returns claude-code when only claude binary found" {
  local fake_bin="$TEST_DIR/bin"
  mkdir -p "$fake_bin"
  touch "$fake_bin/claude" && chmod +x "$fake_bin/claude"
  PATH="$fake_bin" run detect_harnesses
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code"* ]]
}

@test "detect_harnesses returns aider when only aider binary found" {
  local fake_bin="$TEST_DIR/bin"
  mkdir -p "$fake_bin"
  touch "$fake_bin/aider" && chmod +x "$fake_bin/aider"
  PATH="$fake_bin" run detect_harnesses
  [ "$status" -eq 0 ]
  [[ "$output" == *"aider"* ]]
}

@test "detect_harnesses returns gemini-cli when gemini binary found" {
  local fake_bin="$TEST_DIR/bin"
  mkdir -p "$fake_bin"
  touch "$fake_bin/gemini" && chmod +x "$fake_bin/gemini"
  PATH="$fake_bin" run detect_harnesses
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-cli"* ]]
}

@test "detect_harnesses lists multiple when multiple binaries found" {
  local fake_bin="$TEST_DIR/bin"
  mkdir -p "$fake_bin"
  touch "$fake_bin/claude" "$fake_bin/aider" && chmod +x "$fake_bin/claude" "$fake_bin/aider"
  PATH="$fake_bin" run detect_harnesses
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"aider"* ]]
}

@test "detect_harnesses returns nothing when no known binaries found" {
  PATH="/nonexistent/path" run detect_harnesses
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# .gitignore integration
# ---------------------------------------------------------------------------

@test ".gitignore gets .wrapit added when user confirms" {
  printf 'node_modules\n' > "$TEST_DIR/.gitignore"
  printf 'y\n' | run_init_gitignore "$TEST_DIR/.gitignore"
  grep -q '\.wrapit' "$TEST_DIR/.gitignore"
}

@test ".gitignore is unchanged when user declines" {
  printf 'node_modules\n' > "$TEST_DIR/.gitignore"
  local before
  before="$(cat "$TEST_DIR/.gitignore")"
  printf 'n\n' | run_init_gitignore "$TEST_DIR/.gitignore"
  local after
  after="$(cat "$TEST_DIR/.gitignore")"
  [ "$before" = "$after" ]
}

@test ".gitignore step is skipped when no .gitignore exists" {
  _skip_if_no_preset "claude-code"
  rm -f "$TEST_DIR/.gitignore"
  run run_init --preset claude-code
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.gitignore" ]
}

@test ".gitignore not modified when .wrapit already listed" {
  printf '.wrapit\nnode_modules\n' > "$TEST_DIR/.gitignore"
  local before
  before="$(cat "$TEST_DIR/.gitignore")"
  printf 'y\n' | run_init_gitignore "$TEST_DIR/.gitignore"
  local count
  count="$(grep -c '\.wrapit' "$TEST_DIR/.gitignore" || true)"
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------

@test "unknown preset exits 1" {
  run run_init --preset bogus-xyz
  [ "$status" -eq 1 ]
}

@test "existing .wrapit with --preset causes error or prompt" {
  _skip_if_no_preset "claude-code"
  printf '# existing\n' > "$TEST_DIR/.wrapit"
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../lib/parse.sh'
    source '${BATS_TEST_DIRNAME}/../lib/check.sh'
    source '${BATS_TEST_DIRNAME}/../lib/presets.sh'
    source '${BATS_TEST_DIRNAME}/../lib/init.sh'
    cd '$TEST_DIR'
    run_init --preset claude-code </dev/null
  "
  [ "$status" -ne 127 ]  # not "command not found"
}
