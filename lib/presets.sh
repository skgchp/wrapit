#!/usr/bin/env bash
# lib/presets.sh — file-based harness preset loader

# Locate the presets directory relative to this lib file.
_PRESETS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${WRAPIT_PRESETS_DIR:=${_PRESETS_LIB_DIR}/../presets}"

# _parse_frontmatter <file> <key>
# Extracts a value from YAML-style frontmatter between --- delimiters.
# Prints the value and returns 0. Returns 1 if key not found.
_parse_frontmatter() {
  local file="$1"
  local key="$2"
  local in_front=0
  local line fkey fval
  while IFS= read -r line; do
    if [ "$in_front" -eq 0 ] && [ "$line" = "---" ]; then
      in_front=1
      continue
    fi
    if [ "$in_front" -eq 1 ] && [ "$line" = "---" ]; then
      break
    fi
    if [ "$in_front" -eq 1 ]; then
      fkey="${line%%:*}"
      if [ "$fkey" = "$key" ]; then
        fval="${line#*: }"
        printf '%s\n' "$fval"
        return 0
      fi
    fi
  done < "$file"
  return 1
}

# _preset_body <file>
# Prints the content of a preset file after the closing --- frontmatter delimiter.
# Returns 1 if no valid frontmatter structure found.
_preset_body() {
  local file="$1"
  local in_front=0
  local found_end=0
  local line
  while IFS= read -r line; do
    if [ "$found_end" -eq 1 ]; then
      printf '%s\n' "$line"
      continue
    fi
    if [ "$in_front" -eq 0 ] && [ "$line" = "---" ]; then
      in_front=1
      continue
    fi
    if [ "$in_front" -eq 1 ] && [ "$line" = "---" ]; then
      found_end=1
      continue
    fi
  done < "$file"
  [ "$found_end" -eq 1 ] || return 1
}

# list_presets
# Prints one preset name per line for each .preset file in WRAPIT_PRESETS_DIR,
# excluding _-prefixed files (internal files such as _base.preset).
list_presets() {
  local f name
  for f in "$WRAPIT_PRESETS_DIR"/*.preset; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    name="${name%.preset}"
    case "$name" in
      _*) continue ;;
    esac
    printf '%s\n' "$name"
  done
}

# get_preset <name>
# Prints a .wrapit file body for the named harness preset.
# Prepends _base.preset content if it exists.
# Exits 1 for unknown or missing presets.
get_preset() {
  local name="$1"
  local preset_file="${WRAPIT_PRESETS_DIR}/${name}.preset"
  local base_file="${WRAPIT_PRESETS_DIR}/_base.preset"

  if [ ! -f "$preset_file" ]; then
    printf 'wrapit: unknown preset "%s"\n' "$name" >&2
    local available
    available="$(list_presets | tr '\n' ' ')"
    available="${available% }"
    printf 'Available presets: %s\n' "${available:-none}" >&2
    return 1
  fi

  if [ -f "$base_file" ]; then
    _preset_body "$base_file"
    printf '\n'
  fi

  _preset_body "$preset_file"
}
