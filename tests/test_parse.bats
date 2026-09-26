#!/usr/bin/env bats
# tests/test_parse.bats — unit tests for .wrapit config parsing

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  TEST_DIR="$(mktemp -d)"
  # Ensure a real HOME-relative file exists for optional-path tests
  touch "$TEST_DIR/.gitconfig"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Binding directives
# ---------------------------------------------------------------------------

@test "ro directive produces --ro-bind" {
  echo "ro $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind"* ]]
  [[ "$output" == *".gitconfig"* ]]
}

@test "rw directive produces --bind" {
  echo "rw $TEST_DIR" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind"* ]]
  [[ "$output" != *"--ro-bind"* ]]
}

@test "ro? with existing path produces --ro-bind" {
  echo "ro? $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind"* ]]
}

@test "ro? with missing path is silently skipped" {
  echo "ro? /nonexistent/path/$$" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--ro-bind"* ]]
  [[ "$output" != *"--bind"* ]]
}

@test "rw? with missing path is silently skipped" {
  echo "rw? /nonexistent/path/$$" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--bind"* ]]
}

@test "rw? with existing path produces --bind" {
  mkdir -p "$TEST_DIR/existing"
  echo "rw? $TEST_DIR/existing" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind"* ]]
}

@test "ro directive with multiple spaces before path works" {
  echo "ro  $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind"* ]]
  [[ "$output" == *".gitconfig"* ]]
}

# ---------------------------------------------------------------------------
# Comments and blank lines
# ---------------------------------------------------------------------------

@test "comment lines are ignored" {
  printf '# this is a comment\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"# this"* ]]
  [[ "$output" == *"--ro-bind"* ]]
}

@test "blank lines are ignored" {
  printf '\n\nro %s/.gitconfig\n\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
}

@test "empty file exits 0 with no output" {
  > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Section parsing
# ---------------------------------------------------------------------------

@test "[network] enabled=true sets WRAPIT_NETWORK_ENABLED" {
  printf '[network]\nenabled = true\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "true" ]
}

@test "[network] enabled=false sets WRAPIT_NETWORK_ENABLED to false" {
  printf '[network]\nenabled = false\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "false" ]
}

@test "[sandbox] ssh_agent=true sets WRAPIT_SANDBOX_SSH_AGENT" {
  printf '[sandbox]\nssh_agent = true\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_SSH_AGENT" = "true" ]
}

@test "[sandbox] tmpfs_tmp=false sets WRAPIT_SANDBOX_TMPFS_TMP" {
  printf '[sandbox]\ntmpfs_tmp = false\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_TMPFS_TMP" = "false" ]
}

@test "[sandbox] unshare_pid=false sets WRAPIT_SANDBOX_UNSHARE_PID" {
  printf '[sandbox]\nunshare_pid = false\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_UNSHARE_PID" = "false" ]
}

@test "[sandbox] die_with_parent=false sets WRAPIT_SANDBOX_DIE_WITH_PARENT" {
  printf '[sandbox]\ndie_with_parent = false\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_DIE_WITH_PARENT" = "false" ]
}

# ---------------------------------------------------------------------------
# Path expansion
# ---------------------------------------------------------------------------

@test "tilde expands to HOME" {
  touch "$HOME/.gitconfig" 2>/dev/null || true
  echo "ro ~/.gitconfig" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.gitconfig"* ]]
}

@test "PWD expands to current directory" {
  echo "rw \$PWD" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PWD"* ]]
}

@test "XDG_CONFIG_HOME defaults to ~/.config when unset" {
  mkdir -p "$HOME/.config/git" 2>/dev/null || true
  unset XDG_CONFIG_HOME
  echo "ro? \$XDG_CONFIG_HOME/git" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  # Either expands to ~/.config/git or is skipped (dir may not exist) — no error
}

@test "XDG_CONFIG_HOME uses set value" {
  export XDG_CONFIG_HOME="$TEST_DIR/xdg"
  mkdir -p "$TEST_DIR/xdg/git"
  echo "ro \$XDG_CONFIG_HOME/git" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DIR/xdg/git"* ]]
  unset XDG_CONFIG_HOME
}

@test "arbitrary env var is expanded" {
  export WRAPIT_TEST_VAR="$TEST_DIR"
  echo "rw \$WRAPIT_TEST_VAR" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DIR"* ]]
  unset WRAPIT_TEST_VAR
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------

@test "unknown permission prefix exits 1 with error message" {
  echo "xx $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown permission"* ]]
}

@test "malformed line with no space exits 1" {
  echo "nochoice" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
}

@test "non-optional ro path that does not exist exits 1" {
  echo "ro /nonexistent/path/$$" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "non-optional rw path that does not exist exits 1" {
  echo "rw /nonexistent/path/$$" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "non-existent config file exits 1" {
  run parse_wrapit "/nonexistent/.wrapit"
  [ "$status" -ne 0 ]
}

@test "binding output includes source and dest paths" {
  mkdir -p "$TEST_DIR/mydir"
  echo "ro $TEST_DIR/mydir" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  # Path should appear twice in the output (source and destination)
  count=$(echo "$output" | grep -o "$TEST_DIR/mydir" | wc -l)
  [ "$count" -ge 2 ]
}
