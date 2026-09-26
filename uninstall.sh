#!/usr/bin/env bash
# uninstall.sh — removes installed wrapit files

INSTALL_DIR="$HOME/.local/share/wrapit"
BIN_LINK="$HOME/.local/bin/wrapit"
DEFAULTS_DIR="$HOME/.config/wrapit"
PATH_MARKER="# wrapit — added by wrapit install.sh"

printf 'Uninstalling wrapit...\n'

# Remove symlink
if [ -L "$BIN_LINK" ]; then
  rm -f "$BIN_LINK"
  printf '  Removed %s\n' "$BIN_LINK"
fi

# Remove installed files
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  printf '  Removed %s\n' "$INSTALL_DIR"
fi

# Remove PATH blocks from shell configs
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
  if [ -f "$rc" ] && grep -qF "$PATH_MARKER" "$rc" 2>/dev/null; then
    # Remove the marker line and the following export PATH line
    tmp="$(mktemp)"
    awk -v marker="$PATH_MARKER" '
      $0 == marker { skip=2; next }
      skip > 0 { skip--; next }
      { print }
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    printf '  Removed PATH block from %s\n' "$rc"
  fi
done

# Ask about defaults file
if [ -d "$DEFAULTS_DIR" ]; then
  printf '\nRemove user defaults at %s? [y/N] ' "$DEFAULTS_DIR"
  ans=""
  IFS= read -r ans || true
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    rm -rf "$DEFAULTS_DIR"
    printf '  Removed %s\n' "$DEFAULTS_DIR"
  else
    printf '  Keeping %s\n' "$DEFAULTS_DIR"
  fi
fi

printf '\nwrapit uninstalled.\n'
