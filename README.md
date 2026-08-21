# mango-omarchy-setup

Cross-distro bootstrap that reproduces a **mango compositor + ly display manager + Omarchy shell** environment on a fresh minimal TTY install of **Arch Linux, Fedora, or Debian Testing**.

It auto-detects the distro, installs all required packages (skipping anything already present), builds the components that have no distro package (mango, ly, quickshell), and applies your personal configs — **including the configs** — from a single one-liner.

## Files

- `bootstrap.sh` — the installer. Run on the fresh target machine.
- `configs.tgz` — your personal configs (mango, omarchy, shell, dotfiles), bundled in this repo and applied by default.
- `capture.sh` — run on the source machine to refresh `configs.tgz`, then commit + push.
- `README.md` — this file.

## One-script install (configs included by default)

On the fresh target machine (minimal TTY, network up), make sure a fetcher exists, then pipe the script straight into `bash`. It installs mango, ly, quickshell, the Omarchy shell + features, **and applies `configs.tgz`** automatically:

```bash
source /etc/os-release
case $ID in
  arch)    sudo pacman -Sy --noconfirm curl ;;
  fedora)  sudo dnf install -y curl ;;
  debian)   sudo apt-get update && sudo apt-get install -y curl ;;
esac

curl -fsSL https://raw.githubusercontent.com/kan935/mango-omarchy-setup/main/bootstrap.sh | bash
```

To inspect first, download then run:
```bash
curl -fsSL https://raw.githubusercontent.com/kan935/mango-omarchy-setup/main/bootstrap.sh -o ~/bootstrap.sh
bash ~/bootstrap.sh --check          # dry run: detect OS + report package availability
bash ~/bootstrap.sh                  # real install (configs applied from the bundled configs.tgz)
```

To use a different/newer config bundle instead of the bundled one:
```bash
curl -fsSL https://raw.githubusercontent.com/kan935/mango-omarchy-setup/main/bootstrap.sh | bash -s -- --config-url https://<your-url>/configs.tgz
```

### Refreshing the bundled configs
```bash
bash capture.sh        # exports this machine's configs to mango-omarchy-capture/configs.tgz
# curate it, then replace configs.tgz in this repo and:
git add configs.tgz && git commit -m "refresh configs" && git push
```
The installer pulls `configs.tgz` from the repo's `main` branch at runtime, so no separate hosting is needed.

### 3. Reboot and log in via ly
```bash
sudo reboot
```
ly defaults to the `mango` wayland session; with autologin on, it logs you straight in and `omarchy-launch-shell` starts the bar/menu/lock.

## bootstrap.sh options

| Option | Effect |
|---|---|
| `--config-url URL` | Download your `configs.tgz` and apply it (rewrites `/home/mbm` → target home). |
| `--no-autologin` | Disable ly autologin (default: autologin on for the target user). |
| `--repo URL` | Override the Omarchy repo URL. |
| `--check` | Detect OS and report package/component availability, then exit (installs nothing). |
| `--no-reboot` | Suppress the reboot suggestion. |

## What gets installed, per distro

- **mango**: Arch via the **CachyOS repo** (`mangowm`, prebuilt — no AUR); Fedora/Debian built from source (pinned `wlroots 0.19.2` + `scenefx 0.4.1`). The bootstrap adds the CachyOS repo automatically if missing.
- **ly**: Arch via CachyOS/Core (`ly`); Fedora/Debian built from source (zig). Replaces SDDM/GDM/LightDM.
- **Omarchy shell**: cloned from the omarchy repo (**`quattro` branch** by default — that is where `omarchy-clipboard-universal` and other features live; pass `--repo-branch` for a different branch); `bin/` added to `PATH`. `quickshell` installed from CachyOS (`quickshell`) on Arch, best-effort source build elsewhere.
- **Omarchy feature dependencies** (installed automatically): `gum`, `rofi`, `imagemagick`, `python`, `ydotool` (+ `input` group + user service), `networkmanager`, `bluez-utils`, `playerctl`, `swaybg`, `libnotify`, `tesseract` language data (`tesseract-data-eng` on Arch, already in Fedora/Debian), `xdg-utils`, plus a notification daemon (`mako`). These are what make `omarchy-capture-text` (OCR), `omarchy-clipboard-universal`, and the various bar modules work.
- **Wallpaper**: the script writes `~/.local/state/omarchy/current/theme.name` and a `background` symlink from your bundled `~/.config/omarchy/backgrounds/<theme>/` so the wallpaper picker finds images and the shell displays them (this state was previously excluded from the bundle).
- **Omarchy CLI tools** (`omarchy-clipboard-universal`, `omarchy-capture-text`, etc.): shipped by the repo, made callable via `PATH`. Their runtime deps (`jq`, `wtype`, `slurp`, `grim`, `tesseract`, `wl-clipboard`, `cliphist`, `hyprpicker`, …) are installed.
- **Apps**: `foot`, `walker`, `starship`, `fastfetch`, `neovim`, `mpv`, `fzf`, `ripgrep`, and friends.

All package installs are idempotent: already-installed packages are skipped.

## Known limits

- `omarchy pkg add` / `omarchy update` and other pacman-bound helpers do not work off-Arch.
- `quickshell` source build on Fedora/Debian may fail; the script continues and the bar/menu simply won't appear (mango + apps still work).
- `wlroots` is pinned to `0.19.2`, which is why mango is built from source off-Arch.
- `hyprpicker` has no Fedora package, so it is built from source there.
- The bundled `configs.tgz` contains only config/dotfiles (mango, omarchy, shell, small local scripts, icons). Large tool binaries (e.g. `mise`, `gh`, `gum`, `aether`, `herdr`), the re-cloned omarchy repo itself, and large custom font packs are **excluded** to keep the repo small; install those separately or extend `capture.sh` if you need them. Decent default fonts are installed by the script.
- On Arch, **all dependencies install from the CachyOS repo via `pacman` — no AUR helper is used**. If a package is not present in any configured repo (e.g. `bibata-cursor-theme` is AUR-only on Arch and may be absent from CachyOS), it is skipped with a warning instead of falling back to the AUR. That only affects cosmetics (cursor theme); everything functional still installs.

## Verifying before a real run
```bash
bash bootstrap.sh --check
```
Reports, per distro, which packages are installed / available / missing and which source-built components are present.
