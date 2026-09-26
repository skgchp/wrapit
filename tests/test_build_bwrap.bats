#!/usr/bin/env bats
# tests/test_build_bwrap.bats — unit tests for bwrap argument assembly

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/build_bwrap.sh"
  TEST_DIR="$(mktemp -d)"
  touch "$TEST_DIR/.gitconfig"
}

teardown() {
  rm -rf "$TEST_DIR"
  unset WRAPIT_TEST_SSH_AUTH_SOCK
}

# ---------------------------------------------------------------------------
# Helper: write a minimal .wrapit and capture full bwrap arg output
# ---------------------------------------------------------------------------

_minimal_config() {
  printf 'ro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
}

# ---------------------------------------------------------------------------
# User-specified bindings are present
# ---------------------------------------------------------------------------

@test "user ro binding appears in output" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind"*"$TEST_DIR/.gitconfig"* ]]
}

# ---------------------------------------------------------------------------
# Hardcoded minimum mounts
# ---------------------------------------------------------------------------

@test "/usr is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /usr /usr"* ]]
}

@test "/lib is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /lib /lib"* ]]
}

@test "/etc/resolv.conf is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /etc/resolv.conf /etc/resolv.conf"* ]]
}

@test "/etc/hosts is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /etc/hosts /etc/hosts"* ]]
}

@test "/etc/ssl is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /etc/ssl /etc/ssl"* ]]
}

@test "/etc/passwd is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /etc/passwd /etc/passwd"* ]]
}

@test "/etc/group is always ro-bound" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /etc/group /etc/group"* ]]
}

@test "--proc /proc is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--proc /proc"* ]]
}

@test "--dev /dev is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dev /dev"* ]]
}

@test "/lib64 included when it exists" {
  # If /lib64 exists on this system, it should appear; if not, no error
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  if [ -e /lib64 ]; then
    [[ "$output" == *"--ro-bind /lib64 /lib64"* ]]
  fi
}

@test "/bin included when it exists" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  if [ -e /bin ]; then
    [[ "$output" == *"--ro-bind /bin /bin"* ]]
  fi
}

# ---------------------------------------------------------------------------
# tmpfs_tmp toggle
# ---------------------------------------------------------------------------

@test "--tmpfs /tmp present when sandbox.tmpfs_tmp=true" {
  printf '[sandbox]\ntmpfs_tmp = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tmpfs /tmp"* ]]
}

@test "--tmpfs /tmp absent when sandbox.tmpfs_tmp=false" {
  printf '[sandbox]\ntmpfs_tmp = false\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--tmpfs /tmp"* ]]
}

@test "--tmpfs /tmp present by default (no sandbox section)" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tmpfs /tmp"* ]]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

@test "--share-net present when network.enabled=true" {
  printf '[network]\nenabled = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--share-net"* ]]
}

@test "--share-net absent when network.enabled=false" {
  printf '[network]\nenabled = false\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--share-net"* ]]
}

@test "--share-net present by default (no network section)" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--share-net"* ]]
}

# ---------------------------------------------------------------------------
# Sandbox flags
# ---------------------------------------------------------------------------

@test "--unshare-pid present when sandbox.unshare_pid=true" {
  printf '[sandbox]\nunshare_pid = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-pid"* ]]
}

@test "--unshare-pid absent when sandbox.unshare_pid=false" {
  printf '[sandbox]\nunshare_pid = false\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--unshare-pid"* ]]
}

@test "--die-with-parent present when sandbox.die_with_parent=true" {
  printf '[sandbox]\ndie_with_parent = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--die-with-parent"* ]]
}

@test "--die-with-parent absent when sandbox.die_with_parent=false" {
  printf '[sandbox]\ndie_with_parent = false\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--die-with-parent"* ]]
}

# ---------------------------------------------------------------------------
# PWD always rw-mounted and deduplicated
# ---------------------------------------------------------------------------

@test "PWD is always rw-bound even when not in config" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind $PWD $PWD"* ]]
}

@test "explicit rw \$PWD in config is deduplicated" {
  printf 'ro %s/.gitconfig\nrw %s\n' "$TEST_DIR" "$PWD" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  # Count occurrences of "--bind $PWD $PWD"
  count=$(printf '%s\n' "$output" | grep -c "^--bind $PWD $PWD$" || true)
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Always-present setenv / chdir
# ---------------------------------------------------------------------------

@test "--setenv HOME is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv HOME $HOME"* ]]
}

@test "--setenv USER is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv USER $USER"* ]]
}

@test "--setenv PATH is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv PATH"* ]]
}

@test "--chdir is always present" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--chdir $PWD"* ]]
}

# ---------------------------------------------------------------------------
# SSH agent
# ---------------------------------------------------------------------------

@test "SSH agent args present when ssh_agent=true and SSH_AUTH_SOCK set" {
  local sock_dir
  sock_dir="$(mktemp -d)"
  local sock_path="$sock_dir/agent.sock"
  touch "$sock_path"

  printf '[sandbox]\nssh_agent = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"

  SSH_AUTH_SOCK="$sock_path" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind $sock_dir"* ]]
  [[ "$output" == *"--setenv SSH_AUTH_SOCK $sock_path"* ]]

  rm -rf "$sock_dir"
}

@test "SSH agent emits warning when ssh_agent=true but SSH_AUTH_SOCK unset" {
  printf '[sandbox]\nssh_agent = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"

  SSH_AUTH_SOCK="" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"* ]] || [[ "$stderr" == *"warning"* ]] || \
    [[ "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" == *"warning"* ]]
}
