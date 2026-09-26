#!/usr/bin/env bats
# tests/test_argv.bats — unit tests for load_bwrap_argv
#
# These are the regression tests for the --test harness bug: the argv has to be
# built as an array, never through eval, or the sandboxed command's own quoting
# is lost. They need no bwrap, so they run everywhere.

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"
  source "${BATS_TEST_DIRNAME}/../lib/build_bwrap.sh"
  TEST_DIR="$(mktemp -d)"
  touch "$TEST_DIR/.gitconfig"
  export WRAPIT_DEFAULTS_FILE=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

_minimal_config() {
  printf 'ro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
}

# Stands in for bwrap: consumes the sandbox flags, then runs what follows.
_fake_bwrap() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --setenv|--ro-bind|--bind|--ro-bind-try|--bind-try) shift 3 ;;
      --proc|--dev|--tmpfs|--dir|--chdir|--unsetenv) shift 2 ;;
      --*) shift ;;
      *) break ;;
    esac
  done
  "$@"
}

# _setenv_value <NAME> — prints the value the argv assigns to NAME
_setenv_value() {
  local want="$1" i=0 n=${#WRAPIT_BWRAP_ARGV[@]}
  while [ "$i" -lt "$n" ]; do
    if [ "${WRAPIT_BWRAP_ARGV[$i]}" = "--setenv" ] &&
       [ "${WRAPIT_BWRAP_ARGV[$((i + 1))]}" = "$want" ]; then
      printf '%s' "${WRAPIT_BWRAP_ARGV[$((i + 2))]}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# The sandboxed command survives intact
# ---------------------------------------------------------------------------

@test "bash -c receives its whole script as one argument" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  run _fake_bwrap "${WRAPIT_BWRAP_ARGV[@]}" bash -c 'echo "ARGC=$# ARG0=$0"'
  [ "$status" -eq 0 ]
  # Under eval this printed an empty line: bash -c got only "echo".
  [ "$output" = "ARGC=0 ARG0=bash" ]
}

@test "positional arguments after a bash -c script are preserved" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  run _fake_bwrap "${WRAPIT_BWRAP_ARGV[@]}" bash -c 'echo "$1/$2"' sh one two
  [ "$status" -eq 0 ]
  [ "$output" = "one/two" ]
}

@test "shell operators inside a quoted script are not run by the outer shell" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  # Under eval, the && was executed by the calling shell and the redirection
  # below hit the host filesystem.
  run _fake_bwrap "${WRAPIT_BWRAP_ARGV[@]}" bash -c 'echo a && echo b'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "a" ]
  [ "${lines[1]}" = "b" ]
}

@test "a script containing a redirection arrives as one argument" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  # This is what T2 does. Under eval the >> was performed by the calling shell,
  # which appended to the real file on the host on every --test run. Here the
  # whole script must reach the command as a single element.
  local script='printf x >> "$1" 2>/dev/null; [ $? -ne 0 ]'
  set -- "${WRAPIT_BWRAP_ARGV[@]}" bash -c "$script" sh /some/path
  local seen=""
  for arg in "$@"; do
    [ "$arg" = "$script" ] && seen="yes"
  done
  [ "$seen" = "yes" ]
}

@test "argv contains no empty elements" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  local i=0 n=${#WRAPIT_BWRAP_ARGV[@]}
  while [ "$i" -lt "$n" ]; do
    [ -n "${WRAPIT_BWRAP_ARGV[$i]}" ]
    i=$((i + 1))
  done
}

# ---------------------------------------------------------------------------
# Arity-aware splitting
# ---------------------------------------------------------------------------

@test "a --setenv value containing spaces stays a single argument" {
  printf '[env]\nset = GREETING=hello world\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  load_bwrap_argv "$TEST_DIR/.wrapit"
  run _setenv_value GREETING
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "--ro-bind keeps its source and destination as two arguments" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  local i=0 n=${#WRAPIT_BWRAP_ARGV[@]} found=0
  while [ "$i" -lt "$n" ]; do
    if [ "${WRAPIT_BWRAP_ARGV[$i]}" = "--ro-bind" ] &&
       [ "${WRAPIT_BWRAP_ARGV[$((i + 1))]}" = "/usr" ] &&
       [ "${WRAPIT_BWRAP_ARGV[$((i + 2))]}" = "/usr" ]; then
      found=1
    fi
    i=$((i + 1))
  done
  [ "$found" -eq 1 ]
}

@test "flags taking no operand are single argv elements" {
  _minimal_config
  load_bwrap_argv "$TEST_DIR/.wrapit"
  local i=0 n=${#WRAPIT_BWRAP_ARGV[@]} found=0
  while [ "$i" -lt "$n" ]; do
    if [ "${WRAPIT_BWRAP_ARGV[$i]}" = "--die-with-parent" ]; then
      found=1
      # The next element must be another flag, not an operand.
      [ "$((i + 1))" -ge "$n" ] || [[ "${WRAPIT_BWRAP_ARGV[$((i + 1))]}" == --* ]]
    fi
    i=$((i + 1))
  done
  [ "$found" -eq 1 ]
}

@test "load_bwrap_argv fails on an unparseable config" {
  printf 'ro /nonexistent/path/xyz\n' > "$TEST_DIR/.wrapit"
  run load_bwrap_argv "$TEST_DIR/.wrapit"
  [ "$status" -ne 0 ]
}

@test "settings parsed from the config remain visible to the caller" {
  # Not a subshell: --test relies on reading WRAPIT_NETWORK_ENABLED afterwards.
  printf '[network]\nenabled = false\nro %s/.gitconfig\n' "$TEST_DIR" > "$TEST_DIR/.wrapit"
  load_bwrap_argv "$TEST_DIR/.wrapit"
  [ "$WRAPIT_NETWORK_ENABLED" = "false" ]
}
