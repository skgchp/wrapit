#!/usr/bin/env bats
# tests/test_presets.bats — unit tests for harness preset definitions

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/presets.sh"
  TEST_DIR="$(mktemp -d)"
  # Isolated preset dir for mechanism tests
  TEST_PRESETS_DIR="$TEST_DIR/presets"
  mkdir -p "$TEST_PRESETS_DIR"
  cat > "$TEST_PRESETS_DIR/_base.preset" <<'PRESET'
---
name: _base
description: Common base
---
[sandbox]
ssh_agent = true

ro  ~/.gitconfig
ro? ~/.config/git
PRESET
  cat > "$TEST_PRESETS_DIR/test-agent.preset" <<'PRESET'
---
name: test-agent
binary: test-bin
description: Test agent for unit tests
---
# ── Test config ────────────────────────────────────────────────────────────────
# Read/write: test agent credentials.
rw  ~/.test-agent
rw? $PWD
PRESET
  cat > "$TEST_PRESETS_DIR/another-agent.preset" <<'PRESET'
---
name: another-agent
binary: another
description: Another test agent
---
rw  ~/.another
rw? $PWD
PRESET
}

teardown() {
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
# Helper: validate preset output is parseable .wrapit syntax
# ---------------------------------------------------------------------------

_preset_is_valid() {
  local preset_name="$1"
  local content
  content="$(get_preset "$preset_name")"
  printf '%s\n' "$content" > "$TEST_DIR/.wrapit-test"
  sed 's/^ro /ro? /; s/^rw /rw? /' "$TEST_DIR/.wrapit-test" > "$TEST_DIR/.wrapit-lenient"
  run parse_wrapit "$TEST_DIR/.wrapit-lenient"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# _parse_frontmatter — extract key from YAML-style frontmatter
# ---------------------------------------------------------------------------

@test "_parse_frontmatter extracts name field" {
  run _parse_frontmatter "$TEST_PRESETS_DIR/test-agent.preset" "name"
  [ "$status" -eq 0 ]
  [ "$output" = "test-agent" ]
}

@test "_parse_frontmatter extracts binary field" {
  run _parse_frontmatter "$TEST_PRESETS_DIR/test-agent.preset" "binary"
  [ "$status" -eq 0 ]
  [ "$output" = "test-bin" ]
}

@test "_parse_frontmatter extracts description field" {
  run _parse_frontmatter "$TEST_PRESETS_DIR/test-agent.preset" "description"
  [ "$status" -eq 0 ]
  [ "$output" = "Test agent for unit tests" ]
}

@test "_parse_frontmatter returns 1 for missing key" {
  run _parse_frontmatter "$TEST_PRESETS_DIR/test-agent.preset" "nonexistent"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# _preset_body — content after frontmatter delimiter
# ---------------------------------------------------------------------------

@test "_preset_body strips frontmatter and returns body" {
  run _preset_body "$TEST_PRESETS_DIR/test-agent.preset"
  [ "$status" -eq 0 ]
  [[ "$output" != *"---"* ]]
  [[ "$output" != *"name: test-agent"* ]]
  [[ "$output" == *"rw"*"~/.test-agent"* ]]
}

@test "_preset_body does not include frontmatter keys" {
  run _preset_body "$TEST_PRESETS_DIR/test-agent.preset"
  [ "$status" -eq 0 ]
  [[ "$output" != *"binary:"* ]]
  [[ "$output" != *"description:"* ]]
}

# ---------------------------------------------------------------------------
# get_preset — loads from file, prepends base
# ---------------------------------------------------------------------------

@test "get_preset loads preset content from file" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run get_preset "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*"~/.test-agent"* ]]
}

@test "get_preset prepends base content" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run get_preset "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitconfig"* ]]
  [[ "$output" == *"[sandbox]"* ]]
}

@test "get_preset exits 1 for unknown preset" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run get_preset "bogus-harness-xyz"
  [ "$status" -eq 1 ]
}

@test "get_preset unknown preset shows helpful error message" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run get_preset "bogus-harness-xyz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown preset"* ]] || [[ "$output" == *"Unknown preset"* ]]
}

@test "get_preset unknown preset lists available presets in error" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run get_preset "bogus-harness-xyz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-agent"* ]]
}

# ---------------------------------------------------------------------------
# list_presets — discovers available presets from files
# ---------------------------------------------------------------------------

@test "list_presets returns at least one preset name" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run list_presets
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "list_presets returns test-agent" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run list_presets
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-agent"* ]]
}

@test "list_presets does not include _base" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run list_presets
  [ "$status" -eq 0 ]
  [[ "$output" != *"_base"* ]]
}

@test "list_presets returns multiple presets when multiple files exist" {
  WRAPIT_PRESETS_DIR="$TEST_PRESETS_DIR"
  run list_presets
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-agent"* ]]
  [[ "$output" == *"another-agent"* ]]
}

# ---------------------------------------------------------------------------
# Real preset content tests — skipped if preset file not found
# ---------------------------------------------------------------------------

@test "claude-code preset contains rw ~/.claude" {
  _skip_if_no_preset "claude-code"
  run get_preset "claude-code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*".claude"* ]]
}

@test "claude-code preset contains rw? ~/.claude.json" {
  _skip_if_no_preset "claude-code"
  run get_preset "claude-code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw?"*".claude.json"* ]]
}

@test "claude-code preset contains rw ~/.npm" {
  _skip_if_no_preset "claude-code"
  run get_preset "claude-code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*".npm"* ]]
}

@test "claude-code preset contains ro? ~/.nvm" {
  _skip_if_no_preset "claude-code"
  run get_preset "claude-code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ro?"*".nvm"* ]]
}

@test "aider preset contains rw ~/.aider" {
  _skip_if_no_preset "aider"
  run get_preset "aider"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*".aider"* ]]
}

@test "gemini-cli preset contains rw ~/.gemini" {
  _skip_if_no_preset "gemini-cli"
  run get_preset "gemini-cli"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*".gemini"* ]]
}

@test "mistral-vibe preset contains rw ~/.vibe" {
  _skip_if_no_preset "mistral-vibe"
  run get_preset "mistral-vibe"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rw"*".vibe"* ]]
}

@test "goose preset contains rw ~/.config/goose" {
  _skip_if_no_preset "goose"
  run get_preset "goose"
  [ "$status" -eq 0 ]
  [[ "$output" == *".config/goose"* ]]
}

@test "amp preset contains rw ~/.config/amp" {
  _skip_if_no_preset "amp"
  run get_preset "amp"
  [ "$status" -eq 0 ]
  [[ "$output" == *".config/amp"* ]]
}

# ---------------------------------------------------------------------------
# All available presets share common base and produce valid syntax
# (dynamic: no hardcoded preset list)
# ---------------------------------------------------------------------------

@test "all available presets include ro ~/.gitconfig" {
  local preset_list="$TEST_DIR/all-presets.txt"
  list_presets > "$preset_list"
  while IFS= read -r preset; do
    run get_preset "$preset"
    [ "$status" -eq 0 ] || { echo "FAIL: get_preset $preset failed"; return 1; }
    [[ "$output" == *"gitconfig"* ]] || {
      echo "FAIL: preset $preset missing gitconfig"
      return 1
    }
  done < "$preset_list"
}

@test "all available presets include [sandbox] section" {
  local preset_list="$TEST_DIR/all-presets.txt"
  list_presets > "$preset_list"
  while IFS= read -r preset; do
    run get_preset "$preset"
    [ "$status" -eq 0 ] || { echo "FAIL: get_preset $preset failed"; return 1; }
    [[ "$output" == *"[sandbox]"* ]] || {
      echo "FAIL: preset $preset missing [sandbox] section"
      return 1
    }
  done < "$preset_list"
}

@test "all available preset outputs are valid .wrapit syntax" {
  local preset_list="$TEST_DIR/all-presets.txt"
  list_presets > "$preset_list"
  while IFS= read -r preset; do
    _preset_is_valid "$preset" || {
      echo "FAIL: preset $preset produced invalid .wrapit syntax"
      return 1
    }
  done < "$preset_list"
}
