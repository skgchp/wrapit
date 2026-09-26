#!/usr/bin/env bash
# install.sh — user-level wrapit installation (no sudo required)

set -e

INSTALL_DIR="$HOME/.local/share/wrapit"
BIN_DIR="$HOME/.local/bin"
DEFAULTS_DIR="$HOME/.config/wrapit"
DEFAULTS_FILE="$DEFAULTS_DIR/defaults.wrapit"
PATH_MARKER="# wrapit — added by wrapit install.sh"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

NO_PATH=false

_usage() {
  cat <<EOF
Usage: bash install.sh [--no-path] [--help]

  --no-path   Do not touch any shell rc file. Installs everything else and
              prints the PATH line to add yourself. Use this when your dotfiles
              are generated from a template, where an appended block would be
              lost on the next regeneration.
  --help      Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-path) NO_PATH=true; shift ;;
    --help|-h) _usage; exit 0 ;;
    *)
      printf 'install: unknown option: %s\n' "$1" >&2
      _usage >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

_check_bash() {
  local major="${BASH_VERSINFO[0]:-0}"
  local minor="${BASH_VERSINFO[1]:-0}"
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 2 ]; }; then
    printf 'install: requires bash 3.2 or later (found %s)\n' "$BASH_VERSION" >&2
    exit 1
  fi
}

_check_bwrap() {
  if ! command -v bwrap > /dev/null 2>&1; then
    printf 'install: bwrap (bubblewrap) is not installed.\n' >&2
    if [ -f /etc/os-release ]; then
      local id
      id="$(. /etc/os-release && printf '%s' "${ID:-}")"
      case "$id" in
        ubuntu|debian) printf 'Install it with: sudo apt install bubblewrap\n' >&2 ;;
        fedora|rhel|centos) printf 'Install it with: sudo dnf install bubblewrap\n' >&2 ;;
        arch) printf 'Install it with: sudo pacman -S bubblewrap\n' >&2 ;;
        opensuse*) printf 'Install it with: sudo zypper install bubblewrap\n' >&2 ;;
        *) printf 'Install bubblewrap via your distro package manager.\n' >&2 ;;
      esac
    fi
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# PATH block management
# ---------------------------------------------------------------------------

_has_path_block() {
  local rc_file="$1"
  [ -f "$rc_file" ] && grep -qF "$PATH_MARKER" "$rc_file"
}

_add_path_block() {
  local rc_file="$1"
  _has_path_block "$rc_file" && return 0
  printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n' "$PATH_MARKER" >> "$rc_file"
  printf '  Added PATH entry to %s\n' "$rc_file"
}

# ---------------------------------------------------------------------------
# Main installation
# ---------------------------------------------------------------------------

_check_bash
_check_bwrap

printf 'Installing wrapit...\n'

# Copy files
mkdir -p "$INSTALL_DIR"
src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$src_dir/wrapit" "$src_dir/lib" "$src_dir/presets" \
      "$src_dir/install.sh" "$src_dir/uninstall.sh" \
      "$src_dir/fixtures" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/wrapit"
printf '  Installed files to %s\n' "$INSTALL_DIR"

# Create symlink
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/wrapit" "$BIN_DIR/wrapit"
printf '  Created symlink at %s\n' "$BIN_DIR/wrapit"

# Shell PATH config
local_bin_on_path=false
case ":${PATH}:" in
  *":$BIN_DIR:"*) local_bin_on_path=true ;;
esac

if [ "$local_bin_on_path" = "false" ]; then
  if [ "$NO_PATH" = "true" ]; then
    printf '  Skipping shell rc files (--no-path). Add this yourself:\n'
    printf '    export PATH="$HOME/.local/bin:$PATH"\n'
  else
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
      [ -f "$rc" ] && _add_path_block "$rc"
    done
  fi
fi

# User defaults file
mkdir -p "$DEFAULTS_DIR"
if [ ! -f "$DEFAULTS_FILE" ]; then
  cat > "$DEFAULTS_FILE" <<'EOF'
# ~/.config/wrapit/defaults.wrapit
# User-level defaults, merged before every project's .wrapit. The project file
# is parsed second, so it wins on any setting or path these lines also cover.
#
# Keep every binding here optional (ro? / rw?). A plain ro or rw naming a path
# that does not exist is an error, and an error here breaks every project.

[sandbox]
ssh_agent       = true
unshare_pid     = true
unshare_ipc     = true
unshare_uts     = true
unshare_cgroup  = true
die_with_parent = true
tmpfs_tmp       = true

[network]
enabled = true

ro? ~/.gitconfig
ro? ~/.config/git
ro? ~/.nvm
ro? ~/.fnm
ro? ~/.volta
rw? ~/.npm
EOF
  printf '  Created %s\n' "$DEFAULTS_FILE"
fi

printf '\nwrapit %s installed successfully.\n' "$(cat "$INSTALL_DIR/wrapit" | grep '^WRAPIT_VERSION=' | cut -d'"' -f2 || printf 'unknown')"
if [ "$NO_PATH" = "false" ]; then
  printf 'Run: source ~/.bashrc   (or open a new terminal)\n'
fi
printf 'Then: wrapit --help\n'
