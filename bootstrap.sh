#!/bin/bash

set -o pipefail

REPO_URL="${REPO_URL:-https://github.com/basecamp/omarchy}"
REPO_BRANCH="${REPO_BRANCH:-quattro}"
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/kan935/mango-omarchy-setup/main/configs.tgz}"
CHECK=0
AUTOLOGIN=1
NOREBOOT=0
TARGET_USER=""
TARGET_HOME=""

log()  { printf '\033[1;34m[o]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
skip() { printf '\033[1;33m[=]\033[0m skip: %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

FAMILY=""
PM=""

ARCH_PKGS=(
  wayland seatd xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
  foot wl-clipboard cliphist grim slurp brightnessctl pamixer pavucontrol libnotify mako
  jq wtype tesseract tesseract-data-eng starship fastfetch neovim mpv fzf ripgrep git curl
  walker bibata-cursor-theme hyprpicker mangowm quickshell
  gum rofi imagemagick python ydotool networkmanager bluez-utils playerctl swaybg xdg-utils
  noto-fonts noto-fonts-emoji ttf-font-awesome ttf-jetbrains-mono
)
FEDORA_PKGS=(
  meson ninja-build gcc git curl
  seatd xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
  foot wl-clipboard cliphist grim slurp brightnessctl pamixer pavucontrol libnotify mako
  jq wtype tesseract tesseract-langpack-eng starship fastfetch neovim mpv fzf ripgrep
  walker bibata-cursor-theme
  gum rofi ImageMagick python3 python-unversioned-command ydotool NetworkManager bluez playerctl swaybg xdg-utils
  zig pam-devel libxcb-devel xorg-x11-xauth xorg-x11-server-Xwayland
  google-noto-sans-fonts google-noto-emoji-fonts jetbrains-mono-fonts
)
DEBIAN_PKGS=(
  meson ninja-build build-essential pkg-config git curl
  seatd xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
  foot wl-clipboard cliphist grim slurp brightnessctl pamixer pavucontrol libnotify-bin mako
  jq wtype tesseract tesseract-ocr-eng starship fastfetch neovim mpv fzf ripgrep
  walker bibata-cursor-theme hyprpicker
  gum rofi imagemagick python3 python-is-python3 ydotool network-manager bluez playerctl swaybg xdg-utils
  zig libpam0g-dev libxcb-xkb-dev xauth xwayland
  fonts-noto fonts-noto-color-emoji fonts-font-awesome fonts-jetbrains-mono
)

PKGS=()

root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
  fi
  case "$ID" in
    arch|archarm|manjaro)
      FAMILY=arch; PM=pacman ;;
    fedora|fedora-asahi-remix|nobara)
      FAMILY=rpm; PM=dnf ;;
    debian|ubuntu|linuxmint|pop)
      FAMILY=deb; PM=apt ;;
    *)
      if echo "$ID_LIKE" | grep -q arch; then FAMILY=arch; PM=pacman
      elif echo "$ID_LIKE" | grep -q fedora; then FAMILY=rpm; PM=dnf
      elif echo "$ID_LIKE" | grep -q debian; then FAMILY=deb; PM=apt
      else err "Unsupported distro: ID=$ID ID_LIKE=$ID_LIKE"; exit 1
      fi ;;
  esac
  log "Detected distro family: $FAMILY (PM=$PM, ID=$ID)"
}

resolve_target_user() {
  if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  elif [ "$(id -u)" -ne 0 ]; then
    TARGET_USER="$(id -un)"
  else
    TARGET_USER="$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')"
    if [ -n "$TARGET_USER" ]; then
      warn "Running as root with no SUDO_USER; installing Omarchy pieces for login user '$TARGET_USER'."
    else
      TARGET_USER=root
    fi
  fi
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [ -z "$TARGET_HOME" ] && TARGET_HOME=/root
  log "Target user: $TARGET_USER  home: $TARGET_HOME"
}

pm_installed() {
  case "$FAMILY" in
    arch) pacman -Qq "$@" &>/dev/null ;;
    rpm)  rpm -q "$@" &>/dev/null ;;
    deb)  dpkg -s "$@" &>/dev/null ;;
  esac
}

pm_available() {
  case "$FAMILY" in
    arch) pacman -Si "$1" &>/dev/null ;;
    rpm)  dnf list available "$1" &>/dev/null ;;
    deb)  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{c=$2} END{exit (c==""||c=="(none)")?1:0}' ;;
  esac
}

pm_install() {
  local p
  for p in "$@"; do
    if pm_installed "$p"; then skip "$p (already installed)"; continue; fi
    if ! pm_available "$p"; then warn "$p not available in repos - skipping (no AUR fallback by design)"; continue; fi
    ok "installing $p"
    case "$FAMILY" in
      arch) root pacman -S --needed --noconfirm "$p" ;;
      rpm)  root dnf install -y "$p" ;;
      deb)  root apt-get install -y "$p" ;;
    esac
  done
}

ensure_fetcher() {
  case "$FAMILY" in
    arch) pm_installed curl || root pacman -Sy --noconfirm curl git ;;
    rpm)  pm_installed curl || root dnf install -y curl ;;
    deb)  pm_installed curl || { root apt-get update && root apt-get install -y curl; } ;;
  esac
}

setup_cachyos_repo() {
  if grep -q '^\[cachyos\]' /etc/pacman.conf 2>/dev/null; then
    skip "cachyos repo already present in /etc/pacman.conf"
    return 0
  fi
  log "Adding CachyOS repository (prebuilt mango/quickshell/ly etc. via pacman, no AUR)..."
  root pacman-key --init 2>/dev/null || true
  if ! root pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>/dev/null; then
    root pacman-key --recv-keys F3B607488DB35A47 --keyserver hkps://keys.openpgp.org 2>/dev/null \
      || curl -fsSL https://mirror.cachyos.org/cachyos.key -o /tmp/cachyos.key && root pacman-key --add /tmp/cachyos.key
  fi
  root pacman-key --lsign-key F3B607488DB35A47
  root bash -c "printf 'Server = https://mirror.cachyos.org/repo/\$arch\n' > /etc/pacman.d/cachyos-mirrorlist"
  root bash -c "cat >> /etc/pacman.conf" <<'EOF'

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
  root pacman -Sy --noconfirm
  root pacman -S --needed --noconfirm cachyos-keyring cachyos-mirrorlist 2>/dev/null || true
  ok "CachyOS repo enabled"
}

build_dep_wlroots() {
  case "$FAMILY" in
    rpm)
      root dnf builddep -y wlroots 2>/dev/null || pm_install meson ninja-build wayland-devel wayland-protocols-devel libinput-devel libxkbcommon-devel pixman-devel libseat-devel libdrm-devel libdisplay-info-devel libliftoff-devel libxcb-devel libxcb-composite0-devel libxcb-res0-devel libxcb-xfixes0-devel libxcb-errors-devel libxcb-util-devel libxcb-icccm-devel libxcb-image-devel libxcb-randr-devel libxcb-xkb-devel pcre2-devel libpng-devel cairo-devel pango-devel hwdata libcap-devel
      ;;
    deb)
      root apt-get build-dep -y wlroots 2>/dev/null || pm_install meson ninja-build libwayland-dev wayland-protocols libinput-dev libxkbcommon-dev libpixman-1-dev libseat-dev libdrm-dev libdisplay-info-dev libliftoff-dev libxcb-composite0-dev libxcb-res0-dev libxcb-xfixes0-dev libxcb-errors-dev libxcb-util-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-randr0-dev libxcb-xkb-dev libxcb1-dev libpcre2-dev libpng-dev libcairo2-dev libpango1.0-dev hwdata libcap-dev
      ;;
  esac
}

build_from_git() {
  local url="$1" tag="$2" dl="$3" name="$4"
  local bd="/tmp/opencode/build/$name"
  if command -v "$name" >/dev/null 2>&1; then skip "$name (already built)"; return 0; fi
  log "Building $name from source (tag: ${tag:-HEAD})..."
  rm -rf "$bd"; mkdir -p "$bd"
  git clone --depth 1 ${tag:+--branch "$tag"} "$url" "$bd" || { warn "clone failed: $name"; return 1; }
  if [ -f "$bd/meson.build" ]; then
    meson setup "$bd/build" -Dprefix=/usr || { warn "meson setup failed: $name"; return 1; }
    ninja -C "$bd/build" || { warn "build failed: $name"; return 1; }
    root ninja -C "$bd/build" install || { warn "install failed: $name"; return 1; }
  else
    warn "$name has no meson.build; build manually"; return 1
  fi
  command -v "$name" >/dev/null 2>&1 && ok "$name built" || warn "$name binary not found after build"
}

install_mango() {
  if command -v mango >/dev/null 2>&1; then skip "mango (already installed)"; return 0; fi
  case "$FAMILY" in
    arch) pm_install mangowm ;;
    rpm|deb)
      build_dep_wlroots
      build_from_git https://gitlab.freedesktop.org/wlroots/wlroots.git 0.19.2 "" wlroots
      build_from_git https://github.com/wlrfx/scenefx.git 0.4.1 "" scenefx
      build_from_git https://github.com/mangowm/mango.git "" "" mango
      ;;
  esac
  if [ ! -f /usr/share/wayland-sessions/mango.desktop ]; then
    local f
    for f in /usr/share/wayland-sessions/mangowm.desktop /usr/share/wayland-sessions/*mango*.desktop; do
      if [ -f "$f" ]; then root ln -sf "$f" /usr/share/wayland-sessions/mango.desktop; ok "linked $f -> mango.desktop"; break; fi
    done
  fi
}

install_ly() {
  if command -v ly >/dev/null 2>&1; then skip "ly (already installed)"; else
    case "$FAMILY" in
      arch) pm_install ly ;;
      rpm|deb)
        local bd="/tmp/opencode/build/ly"
        rm -rf "$bd"; mkdir -p "$bd"
        git clone --recurse-submodules https://github.com/fairyglade/ly.git "$bd" || { warn "ly clone failed"; return 1; }
        ( cd "$bd" && zig build installexe -Dinit_system=systemd ) || { warn "ly build failed"; return 1; }
        ok "ly built"
        ;;
    esac
  fi
}

install_quickshell() {
  if command -v quickshell >/dev/null 2>&1; then skip "quickshell (already installed)"; return 0; fi
  case "$FAMILY" in
    arch) pm_install quickshell; return $? ;;
  esac
  warn "Quickshell source build is best-effort on $FAMILY; if it fails the bar/menu will not run but mango + apps will."
  local bd="/tmp/opencode/build/quickshell"
  rm -rf "$bd"; mkdir -p "$bd"
  case "$FAMILY" in
    rpm) pm_install qt6-qtbase-devel qt6-qtdeclarative-devel rust cargo ;;
    deb) pm_install qt6-base-dev qt6-declarative-dev cargo rustc ;;
  esac
  git clone --depth 1 https://github.com/quickshell-mobile/quickshell.git "$bd" || { warn "quickshell clone failed"; return 1; }
  ( cd "$bd" && cargo build --release ) || { warn "quickshell build failed - continuing without it"; return 1; }
  root cp "$bd/target/release/quickshell" /usr/local/bin/quickshell 2>/dev/null || warn "quickshell binary copy failed"
}

install_hyprpicker_fedora() {
  if [ "$FAMILY" != "rpm" ]; then return 0; fi
  if command -v hyprpicker >/dev/null 2>&1; then skip "hyprpicker (already installed)"; return 0; fi
  if pm_available hyprpicker && pm_installed hyprpicker; then return 0; fi
  log "Building hyprpicker from source (not in Fedora repos)..."
  local bd="/tmp/opencode/build/hyprpicker"
  rm -rf "$bd"; mkdir -p "$bd"
  pm_install meson ninja-build wayland-devel wayland-protocols-devel cairo-devel pango-devel libxkbcommon-devel
  git clone --depth 1 https://github.com/hyprwm/hyprpicker.git "$bd" || { warn "hyprpicker clone failed"; return 1; }
  ( cd "$bd" && meson setup build && ninja -C build && root ninja -C build install ) || warn "hyprpicker build failed"
}

setup_omarchy_env() {
  local envd="$TARGET_HOME/.config/environment.d"
  root mkdir -p "$envd"; root chown -R "$TARGET_USER:" "$envd"
  local f="$envd/omarchy.conf"
  if ! root bash -c "grep -q OMARCHY_PATH '$f'" 2>/dev/null; then
    root bash -c "printf 'OMARCHY_PATH=%s/.local/share/omarchy\nPATH=%s/.local/share/omarchy/bin:\$PATH\n' '$TARGET_HOME' '$TARGET_HOME' > '$f'"
    root chown "$TARGET_USER:" "$f"
    ok "wrote $f (session environment for ly/mango)"
  else
    skip "omarchy env already in $f"
  fi
  local rc
  for rc in "$TARGET_HOME/.profile" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.bash_profile"; do
    root touch "$rc"; root chown "$TARGET_USER:" "$rc"
    if ! root bash -c "grep -q OMARCHY_PATH '$rc'"; then
      root bash -c "cat >> '$rc'" <<EOF
export OMARCHY_PATH="\$HOME/.local/share/omarchy"
export PATH="\$HOME/.local/share/omarchy/bin:\$PATH"
EOF
      ok "added omarchy PATH to $rc"
    else
      skip "omarchy PATH already in $rc"
    fi
  done
}

install_default_mango_config() {
  local cfg="$TARGET_HOME/.config/mango"
  if [ -f "$cfg/config.conf" ]; then skip "mango config already present (not overwriting)"; return 0; fi
  root mkdir -p "$cfg"; root chown -R "$TARGET_USER:" "$cfg"
  root bash -c "printf 'exec-once=~/.config/mango/autostart.sh\n' > '$cfg/config.conf'"
  root bash -c "cat > '$cfg/autostart.sh'" <<'EOF'
#!/bin/bash
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE 2>/dev/null
omarchy-launch-shell &
EOF
  root chmod +x "$cfg/autostart.sh"; root chown "$TARGET_USER:" "$cfg/autostart.sh"
  ok "created default mango config that launches omarchy-shell (apply your own via --config-url for full setup)"
}

install_omarchy_shell() {
  local dest="$TARGET_HOME/.local/share/omarchy"
  local need_clone=0
  if [ ! -d "$dest/.git" ]; then
    need_clone=1
  else
    local cur_branch cur_url
    cur_branch="$(sudo -u "$TARGET_USER" git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    cur_url="$(sudo -u "$TARGET_USER" git -C "$dest" remote get-url origin 2>/dev/null)"
    if [ "$cur_branch" != "$REPO_BRANCH" ] || [ "$cur_url" != "$REPO_URL" ]; then
      log "omarchy repo mismatch (has '$cur_branch' @ $cur_url); re-cloning $REPO_URL @ $REPO_BRANCH"
      rm -rf "$dest"; need_clone=1
    fi
  fi
  if [ "$need_clone" = 1 ]; then
    log "Cloning omarchy repo -> $dest"
    root mkdir -p "$dest"
    root chown -R "$TARGET_USER:" "$dest"
    sudo -u "$TARGET_USER" git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$dest" || { warn "omarchy clone failed"; return 1; }
  else
    skip "omarchy repo (already present, branch $REPO_BRANCH)"
  fi
  setup_omarchy_env
  install_quickshell
}

apply_configs() {
  if [ -z "$CONFIG_URL" ]; then
    warn "No --config-url provided; skipping personal configs (system layer installed only)."
    return 0
  fi
  local tmp; tmp="$(mktemp -d)"
  log "Downloading configs from $CONFIG_URL"
  curl -fsSL "$CONFIG_URL" -o "$tmp/configs.tgz" || { warn "config download failed"; return 1; }
  root tar xzf "$tmp/configs.tgz" -C "$TARGET_HOME"
  root chown -R "$TARGET_USER:" "$TARGET_HOME/.config" "$TARGET_HOME/.local" 2>/dev/null
  if [ "$TARGET_HOME" != "/home/mbm" ]; then
    log "Rewriting /home/mbm -> $TARGET_HOME in configs"
    find "$TARGET_HOME/.config" "$TARGET_HOME/.local" -type f \( -name '*.conf' -o -name '*.sh' -o -name '*.json' -o -name '*.toml' -o -name '*.ini' \) \
      -exec sed -i "s#/home/mbm#$TARGET_HOME#g" {} + 2>/dev/null
  fi
  if [ -f "$TARGET_HOME/mango.desktop" ]; then
    root install -Dm644 "$TARGET_HOME/mango.desktop" /usr/share/wayland-sessions/mango.desktop
    ok "installed mango.desktop session"
  fi
  ok "personal configs applied"
}

setup_ydotool() {
  if ! command -v ydotool >/dev/null 2>&1; then skip "ydotool (not installed)"; return 0; fi
  if ! getent group input >/dev/null 2>&1; then root groupadd input 2>/dev/null || true; fi
  if ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx input; then
    root usermod -aG input "$TARGET_USER" && ok "added $TARGET_USER to input group (needed by ydotool; re-login to apply)"
  fi
  if [ -f /usr/lib/systemd/user/ydotool.service ]; then
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
      systemctl --user enable ydotool.service 2>/dev/null || true
    ok "enabled ydotool user service (best-effort)"
  fi
}

setup_omarchy_state() {
  local state="$TARGET_HOME/.local/state/omarchy/current"
  root mkdir -p "$state" "$TARGET_HOME/.cache/omarchy"
  root chown -R "$TARGET_USER:" "$TARGET_HOME/.local/state" "$TARGET_HOME/.cache/omarchy" 2>/dev/null
  local theme="" bg=""
  if [ -d "$TARGET_HOME/.config/omarchy/backgrounds" ]; then
    for d in "$TARGET_HOME/.config/omarchy/backgrounds"/*; do
      [ -d "$d" ] || continue
      bg="$(find -L "$d" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.jpeg' \) 2>/dev/null | head -n1)"
      if [ -n "$bg" ]; then theme="$(basename "$d")"; break; fi
    done
  fi
  if [ -z "$theme" ] && [ -d "$TARGET_HOME/.config/omarchy/themes" ]; then
    theme="$(find "$TARGET_HOME/.config/omarchy/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n1)"
    [ -n "$theme" ] && theme="$(basename "$theme")"
  fi
  if [ -n "$theme" ]; then
    echo "$theme" | root tee "$state/theme.name" >/dev/null
    root chown "$TARGET_USER:" "$state/theme.name"
    ok "omarchy current theme set: $theme"
  fi
  if [ -n "$bg" ]; then
    root ln -nsf "$bg" "$state/background"
    root chown -h "$TARGET_USER:" "$state/background" 2>/dev/null
    ok "omarchy current background link set"
  fi
}

configure_ly() {
  log "Configuring ly display manager..."
  for dm in sddm gdm lightdm; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${dm}.service.*enabled"; then
      root systemctl disable "${dm}.service"
      ok "disabled $dm"
    fi
  done
  root systemctl disable getty@tty2.service 2>/dev/null
  case "$FAMILY" in
    arch) root systemctl enable ly@tty2.service ;;
    *)    root systemctl enable ly.service ;;
  esac
  if [ "$AUTOLOGIN" = "1" ]; then
    local cfg=/etc/ly/config.ini
    root bash -c "touch '$cfg'"
    if ! grep -q '^\[login\]' "$cfg"; then
      root bash -c "printf '\n[login]\n' >> '$cfg'"
    fi
    root bash -c "sed -i '/^\[login\]/,/^\[/ { /^autologin/d; /^user /d }' '$cfg'"
    root bash -c "sed -i \"/^\[login\]/a autologin = true\nuser = $TARGET_USER\" '$cfg'"
    ok "ly autologin enabled for $TARGET_USER"
  fi
}

run_check() {
  detect_os
  resolve_target_user
  echo "=== Distro: $FAMILY ($ID) ==="
  echo "=== Package availability (installed or in repos) ==="
  local p
  for p in "${PKGS[@]}"; do
    if pm_installed "$p"; then echo "INSTALLED : $p"
    elif pm_available "$p"; then echo "AVAILABLE : $p"
    else echo "MISSING   : $p"
    fi
  done
  echo "=== Source-built components (binary presence) ==="
  for b in mango ly quickshell hyprpicker; do
    command -v "$b" >/dev/null 2>&1 && echo "PRESENT   : $b" || echo "ABSENT    : $b"
  done
  echo "=== Done (check mode, nothing installed) ==="
  exit 0
}

usage() {
  cat <<EOF
bootstrap.sh - cross-distro mango + ly + Omarchy installer

Usage: bash bootstrap.sh [options]

Options:
  --config-url URL   URL to your configs.tgz (private). If omitted, only the
                     system layer (mango/ly/omarchy shell/apps) is installed.
  --no-autologin     Disable ly autologin (default: autologin on for target user)
  --repo URL         Omarchy repo URL (default: $REPO_URL)
  --repo-branch B    Omarchy repo branch to clone (default: $REPO_BRANCH)
  --check            Detect OS and report package/component availability, then exit.
  --no-reboot        Do not print reboot suggestion at the end.
  -h, --help         Show this help.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --config-url) CONFIG_URL="$2"; shift 2 ;;
      --no-autologin) AUTOLOGIN=0; shift ;;
      --repo) REPO_URL="$2"; shift 2 ;;
      --repo-branch) REPO_BRANCH="$2"; shift 2 ;;
      --check) CHECK=1; shift ;;
      --no-reboot) NOREBOOT=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown arg: $1"; usage; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"
  detect_os
  resolve_target_user
  case "$FAMILY" in
    arch) PKGS=("${ARCH_PKGS[@]}") ;;
    rpm)  PKGS=("${FEDORA_PKGS[@]}") ;;
    deb)  PKGS=("${DEBIAN_PKGS[@]}") ;;
  esac
  [ "$CHECK" = "1" ] && run_check

  ensure_fetcher
  case "$FAMILY" in
    arch) setup_cachyos_repo ;;
    deb)  root apt-get update ;;
  esac

  log "Phase 1: base packages"
  pm_install "${PKGS[@]}"

  log "Phase 2: mango compositor"
  install_mango

  log "Phase 3: hyprpicker (Fedora source build if missing)"
  install_hyprpicker_fedora

  log "Phase 4: ly display manager"
  install_ly
  configure_ly

  log "Phase 5: Omarchy shell + Quickshell"
  install_omarchy_shell

  log "Phase 6: personal configs"
  apply_configs
  if [ -z "$CONFIG_URL" ]; then
    log "Phase 7: default mango config (no --config-url given)"
    install_default_mango_config
  fi

  log "Phase 8: omarchy runtime state (theme/background, ydotool)"
  setup_omarchy_state
  setup_ydotool

  log "Phase 9: network/notification services"
  if command -v NetworkManager >/dev/null 2>&1; then
    root systemctl enable --now NetworkManager 2>/dev/null || true
  fi

  root systemctl daemon-reload
  ok "Installation complete."
  if [ "$NOREBOOT" != "1" ]; then
    log "Reboot now (e.g. 'sudo reboot') and log in via ly; mango + omarchy-shell should start."
  fi
}

main "$@"
