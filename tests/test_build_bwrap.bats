#!/usr/bin/env bats
# tests/test_build_bwrap.bats — unit tests for bwrap argument assembly

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/build_bwrap.sh"
  TEST_DIR="$(mktemp -d)"
  touch "$TEST_DIR/.gitconfig"
  # The user defaults file is merged into every run, so tests must not pick up
  # whatever the developer happens to have installed.
  export WRAPIT_DEFAULTS_FILE=""
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

# ---------------------------------------------------------------------------
# Extra namespaces
# ---------------------------------------------------------------------------

@test "--unshare-ipc, --unshare-uts and --unshare-cgroup-try present by default" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-ipc"* ]]
  [[ "$output" == *"--unshare-uts"* ]]
  [[ "$output" == *"--unshare-cgroup-try"* ]]
}

@test "--unshare-all is never used" {
  # It would also imply --unshare-user-try, which changes uid mapping.
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--unshare-all"* ]]
}

@test "each extra namespace has a working escape hatch" {
  printf '[sandbox]\nunshare_ipc = false\nunshare_uts = false\nunshare_cgroup = false\nro %s/.gitconfig\n' \
    "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--unshare-ipc"* ]]
  [[ "$output" != *"--unshare-uts"* ]]
  [[ "$output" != *"--unshare-cgroup"* ]]
  # PID isolation is independent of the three above.
  [[ "$output" == *"--unshare-pid"* ]]
}

# ---------------------------------------------------------------------------
# /etc allow-list
# ---------------------------------------------------------------------------

@test "distro-dependent /etc paths are bound when they exist" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  for p in /etc/nsswitch.conf /etc/alternatives /etc/localtime /etc/ca-certificates.conf; do
    if [ -e "$p" ]; then
      [[ "$output" == *"--ro-bind $p $p"* ]]
    else
      [[ "$output" != *"--ro-bind $p $p"* ]]
    fi
  done
}

# ---------------------------------------------------------------------------
# [env]
# ---------------------------------------------------------------------------

@test "no --clearenv without an [env] section" {
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--clearenv"* ]]
}

@test "[env] clear = true emits --clearenv" {
  printf '[env]\nclear = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--clearenv"* ]]
}

@test "--clearenv precedes every --setenv" {
  printf '[env]\nclear = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  local clear_line setenv_line
  clear_line="$(printf '%s\n' "$output" | grep -n -- '^--clearenv$' | head -1 | cut -d: -f1)"
  setenv_line="$(printf '%s\n' "$output" | grep -n -- '^--setenv ' | head -1 | cut -d: -f1)"
  [ -n "$clear_line" ]
  [ "$clear_line" -lt "$setenv_line" ]
}

@test "[env] pass forwards a variable that is set" {
  printf '[env]\nclear = true\npass = WRAPIT_TEST_VAR\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  WRAPIT_TEST_VAR=present run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv WRAPIT_TEST_VAR present"* ]]
}

@test "[env] pass skips a variable that is unset" {
  printf '[env]\nclear = true\npass = WRAPIT_TEST_UNSET\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WRAPIT_TEST_UNSET"* ]]
}

@test "[env] pass does not forward unlisted variables when clear = true" {
  printf '[env]\nclear = true\npass = WRAPIT_TEST_VAR\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  WRAPIT_TEST_VAR=present WRAPIT_TEST_SECRET=leaked run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" != *"leaked"* ]]
}

@test "[env] set emits a literal value" {
  printf '[env]\nset = WRAPIT_PROFILE=devbox\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv WRAPIT_PROFILE devbox"* ]]
}

@test "[env] file emits each KEY=VALUE line" {
  printf 'WRAPIT_FROM_FILE=filevalue\n# comment\n\nWRAPIT_QUOTED="quoted value"\n' > "$TEST_DIR/env"
  chmod 600 "$TEST_DIR/env"
  printf '[env]\nfile = %s/env\nro %s/.gitconfig\n' "$TEST_DIR" "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--setenv WRAPIT_FROM_FILE filevalue"* ]]
  [[ "$output" == *"--setenv WRAPIT_QUOTED quoted value"* ]]
  [[ "$output" != *"comment"* ]]
}

@test "[env] file that does not exist is an error" {
  printf '[env]\nfile = %s/nope\nro %s/.gitconfig\n' "$TEST_DIR" "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
}

@test "[env] set overrides [env] pass for the same name" {
  printf '[env]\nclear = true\npass = WRAPIT_TEST_VAR\nset = WRAPIT_TEST_VAR=wins\nro %s/.gitconfig\n' \
    "$TEST_DIR" > "$TEST_DIR/.wrapit"
  WRAPIT_TEST_VAR=loses run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  # bwrap applies the last --setenv, so set must come after pass.
  local pass_line set_line
  pass_line="$(printf '%s\n' "$output" | grep -n -- '--setenv WRAPIT_TEST_VAR loses' | cut -d: -f1)"
  set_line="$(printf '%s\n' "$output" | grep -n -- '--setenv WRAPIT_TEST_VAR wins' | cut -d: -f1)"
  [ "$pass_line" -lt "$set_line" ]
}

# ---------------------------------------------------------------------------
# Directive order
# ---------------------------------------------------------------------------

@test "a ro override after an rw mount is emitted after it" {
  mkdir -p "$TEST_DIR/tree"
  touch "$TEST_DIR/tree/pinned.json"
  printf 'rw %s/tree\nro %s/tree/pinned.json\n' "$TEST_DIR" "$TEST_DIR" > "$TEST_DIR/.wrapit"
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  local rw_line ro_line
  rw_line="$(printf '%s\n' "$output" | grep -n -- "^--bind $TEST_DIR/tree $TEST_DIR/tree$" | cut -d: -f1)"
  ro_line="$(printf '%s\n' "$output" | grep -n -- "^--ro-bind $TEST_DIR/tree/pinned.json" | cut -d: -f1)"
  [ -n "$rw_line" ]
  [ -n "$ro_line" ]
  [ "$rw_line" -lt "$ro_line" ]
}

@test "the implicit \$PWD mount precedes user directives" {
  # Otherwise a ro directive could not carve a hole inside the working directory.
  _minimal_config
  run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  local pwd_line user_line
  pwd_line="$(printf '%s\n' "$output" | grep -n -- "^--bind $PWD $PWD$" | cut -d: -f1)"
  user_line="$(printf '%s\n' "$output" | grep -n -- "gitconfig" | head -1 | cut -d: -f1)"
  [ "$pwd_line" -lt "$user_line" ]
}

# ---------------------------------------------------------------------------
# User defaults merging
# ---------------------------------------------------------------------------

@test "bindings from the defaults file are merged in" {
  touch "$TEST_DIR/from-defaults"
  printf 'ro %s/from-defaults\n' "$TEST_DIR" > "$TEST_DIR/defaults.wrapit"
  _minimal_config
  WRAPIT_DEFAULTS_FILE="$TEST_DIR/defaults.wrapit" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DIR/from-defaults"* ]]
  [[ "$output" == *"$TEST_DIR/.gitconfig"* ]]
}

@test "the project config wins over the defaults file on a setting" {
  printf '[network]\nenabled = false\n' > "$TEST_DIR/defaults.wrapit"
  printf '[network]\nenabled = true\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  WRAPIT_DEFAULTS_FILE="$TEST_DIR/defaults.wrapit" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--share-net"* ]]
  [[ "$output" != *"--unshare-net"* ]]
}

@test "defaults bindings are emitted before project bindings" {
  touch "$TEST_DIR/from-defaults"
  printf 'ro %s/from-defaults\n' "$TEST_DIR" > "$TEST_DIR/defaults.wrapit"
  _minimal_config
  WRAPIT_DEFAULTS_FILE="$TEST_DIR/defaults.wrapit" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
  local d_line p_line
  d_line="$(printf '%s\n' "$output" | grep -n -- "from-defaults" | head -1 | cut -d: -f1)"
  p_line="$(printf '%s\n' "$output" | grep -n -- "gitconfig" | head -1 | cut -d: -f1)"
  [ "$d_line" -lt "$p_line" ]
}

@test "an empty WRAPIT_DEFAULTS_FILE disables the merge" {
  printf 'ro /nonexistent/would/fail\n' > "$TEST_DIR/defaults.wrapit"
  _minimal_config
  WRAPIT_DEFAULTS_FILE="" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -eq 0 ]
}

@test "an error in the defaults file fails the build" {
  printf 'ro /nonexistent/would/fail\n' > "$TEST_DIR/defaults.wrapit"
  _minimal_config
  WRAPIT_DEFAULTS_FILE="$TEST_DIR/defaults.wrapit" run build_bwrap_args "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
