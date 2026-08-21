#!/bin/bash

set -o pipefail

OUT="$(pwd)/mango-omarchy-capture"
mkdir -p "$OUT"

log() { printf '\033[1;34m[o]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

cd "$HOME" || exit 1

log "Dumping explicit package list..."
pacman -Qqe > "$OUT/pkg-explicit.txt" 2>/dev/null || warn "pacman -Qqe failed (not on Arch?)"
pacman -Qqm > "$OUT/pkg-aur.txt" 2>/dev/null || true

log "Recording mango / quickshell provenance..."
{
  echo "mango: $(pacman -Qo "$(command -v mango 2>/dev/null)" 2>/dev/null || echo unknown)"
  echo "quickshell: $(pacman -Qo "$(command -v quickshell 2>/dev/null)" 2>/dev/null || echo unknown)"
  echo "hyprpicker: $(pacman -Qo "$(command -v hyprpicker 2>/dev/null)" 2>/dev/null || echo unknown)"
} > "$OUT/provenance.txt"

log "Archiving configs..."
# We intentionally do NOT bundle:
#   .local/share/omarchy  -> re-cloned fresh by the installer (quattro branch)
#   .local/share/fonts    -> huge; installed via distro font packages
#   .local/bin/mise,gh,gum -> huge binaries; gh/gum installed via packages,
#                             mise is an optional dev tool (skip to keep size down)
tar czf "$OUT/configs.tgz" \
  --exclude='.cache' --exclude='.var' --exclude='.local/state' \
  --exclude='.local/share/omarchy' \
  --exclude='.local/share/fonts' \
  --exclude='.local/bin/mise' --exclude='.local/bin/gh' --exclude='.local/bin/gum' \
  --exclude='.config/herdr/*.sock' --exclude='.config/herdr/*.log' \
  --exclude='.config/net.imput.helium' \
  --exclude='.config/opencode/node_modules' \
  --exclude='.config/*/CacheStorage' --exclude='.config/*/GPUCache' --exclude='.config/*/Service Worker' \
  .config .local/bin .local/share/applications .local/share/icons \
  .XCompose .bashrc .profile 2>/dev/null
echo "configs.tgz size: $(du -h "$OUT/configs.tgz" | cut -f1)"

if [ -f /usr/share/wayland-sessions/mango.desktop ]; then
  cp /usr/share/wayland-sessions/mango.desktop "$OUT/mango.desktop"
  ok "copied mango.desktop"
fi

ok "Capture complete in: $OUT"
log "Upload configs.tgz + mango.desktop to private storage, then run on target:"
echo "  bash bootstrap.sh --config-url https://<your-private-url>/configs.tgz"
