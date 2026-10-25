#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash restore-dotfiles.sh [--dry-run] [--force]

Copies the curated public dotfiles into $HOME. Existing files are skipped by default.
  --dry-run  Show the files that would be copied
  --force    Overwrite existing regular files
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

FILES=(
  .zshrc
  .config/starship.toml
  .config/ghostty/config
  .config/otty/config.toml
  .config/otty/themes/one-dark.ottytheme
  .config/otty/themes/nord.ottytheme
  .config/git/ignore
  .config/zed/settings.json
  "Library/Application Support/Code/User/settings.json"
)

for file in "${FILES[@]}"; do
  source="$ROOT/dotfiles/$file"
  [[ -f "$source" && ! -L "$source" ]] || { echo "Missing or unsafe source: dotfiles/$file" >&2; exit 1; }
  target="$HOME/$file"
  [[ ! -L "$target" ]] || { echo "Refusing symlink target: $target" >&2; exit 1; }
  if [[ -e "$target" && ! -f "$target" ]]; then
    echo "Target is not a regular file: $target" >&2
    exit 1
  fi
done

for file in "${FILES[@]}"; do
  source="$ROOT/dotfiles/$file"
  target="$HOME/$file"
  if [[ -e "$target" && "$FORCE" -eq 0 ]]; then
    echo "Skip existing: $target (use --force to overwrite)"
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Would copy: $source -> $target"
  else
    mkdir -p "$(dirname "$target")"
    ditto "$source" "$target"
    echo "Copied: $target"
  fi
done
