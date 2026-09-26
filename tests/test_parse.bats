#!/usr/bin/env bats
# tests/test_parse.bats — unit tests for .wrapit config parsing

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  TEST_DIR="$(mktemp -d)"
  # The user defaults file is merged into every run, so tests must not pick up
  # whatever the developer happens to have installed.
  export WRAPIT_DEFAULTS_FILE=""
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

# ---------------------------------------------------------------------------
# [sandbox] namespace keys
# ---------------------------------------------------------------------------

@test "unshare_ipc, unshare_uts and unshare_cgroup default to true" {
  echo "ro $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_UNSHARE_IPC" = "true" ]
  [ "$WRAPIT_SANDBOX_UNSHARE_UTS" = "true" ]
  [ "$WRAPIT_SANDBOX_UNSHARE_CGROUP" = "true" ]
}

@test "the namespace keys can be turned off" {
  printf '[sandbox]\nunshare_ipc = false\nunshare_uts = false\nunshare_cgroup = false\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_SANDBOX_UNSHARE_IPC" = "false" ]
  [ "$WRAPIT_SANDBOX_UNSHARE_UTS" = "false" ]
  [ "$WRAPIT_SANDBOX_UNSHARE_CGROUP" = "false" ]
}

# ---------------------------------------------------------------------------
# [env]
# ---------------------------------------------------------------------------

@test "[env] clear defaults to false" {
  echo "ro $TEST_DIR/.gitconfig" > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_CLEAR" = "false" ]
}

@test "[env] clear is read" {
  printf '[env]\nclear = true\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_CLEAR" = "true" ]
}

@test "[env] pass keeps variable names in their original case" {
  printf '[env]\npass = TZ ANTHROPIC_API_KEY\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_PASS" = "TZ ANTHROPIC_API_KEY" ]
}

@test "repeated [env] pass keys accumulate" {
  printf '[env]\npass = TZ\npass = COLORTERM\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_PASS" = "TZ COLORTERM" ]
}

@test "[env] set keeps its value case and spaces" {
  printf '[env]\nset = Greeting=Hello World\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_SET" = "Greeting=Hello World" ]
}

@test "repeated [env] set keys accumulate one per line" {
  printf '[env]\nset = A=1\nset = B=2\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$(printf '%s' "$WRAPIT_ENV_SET" | wc -l | tr -d ' ')" = "1" ]
  [[ "$WRAPIT_ENV_SET" == *"A=1"* ]]
  [[ "$WRAPIT_ENV_SET" == *"B=2"* ]]
}

@test "[env] set without an = is a parse error" {
  printf '[env]\nset = NOTAPAIR\n' > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
}

@test "[env] file keeps its path case" {
  printf '[env]\nfile = ~/.config/Wrapit/env\n' > "$TEST_DIR/.wrapit"
  parse_wrapit "$TEST_DIR/.wrapit" > /dev/null
  [ "$WRAPIT_ENV_FILE" = "~/.config/Wrapit/env" ]
}

# ---------------------------------------------------------------------------
# Global reset / --keep-globals
# ---------------------------------------------------------------------------

@test "parse_wrapit resets settings from a previous parse by default" {
  printf '[network]\nenabled = false\n' > "$TEST_DIR/a.wrapit"
  printf 'ro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/b.wrapit"
  parse_wrapit "$TEST_DIR/a.wrapit" > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "false" ]
  parse_wrapit "$TEST_DIR/b.wrapit" > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "true" ]
}

@test "--keep-globals carries settings across files so they can be merged" {
  printf '[network]\nenabled = false\n' > "$TEST_DIR/a.wrapit"
  printf 'ro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/b.wrapit"
  reset_wrapit_globals
  parse_wrapit "$TEST_DIR/a.wrapit" --keep-globals > /dev/null
  parse_wrapit "$TEST_DIR/b.wrapit" --keep-globals > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "false" ]
}

@test "a later file overrides an earlier one under --keep-globals" {
  printf '[network]\nenabled = false\n' > "$TEST_DIR/a.wrapit"
  printf '[network]\nenabled = true\n' > "$TEST_DIR/b.wrapit"
  reset_wrapit_globals
  parse_wrapit "$TEST_DIR/a.wrapit" --keep-globals > /dev/null
  parse_wrapit "$TEST_DIR/b.wrapit" --keep-globals > /dev/null
  [ "$WRAPIT_NETWORK_ENABLED" = "true" ]
}

# ---------------------------------------------------------------------------
# Whitespace
# ---------------------------------------------------------------------------

@test "a tab between permission and path is accepted" {
  printf 'ro\t%s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run parse_wrapit "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind $TEST_DIR/.gitconfig"* ]]
}
