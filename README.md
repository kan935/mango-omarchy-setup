# mango-omarchy-setup

Cross-distro bootstrap that reproduces a **mango compositor + ly display manager + Omarchy shell** environment on a fresh minimal TTY install of **Arch Linux, Fedora, or Debian Testing**.

It auto-detects the distro, installs all required packages (skipping anything already present), builds the components that have no distro package (mango, ly, quickshell), and optionally pulls your personal configs from a private URL.

## Files

- `bootstrap.sh` — the installer. Run on the fresh target machine.
- `capture.sh` — run **once on your source Arch/Omarchy laptop** to export your configs + package lists.
- `README.md` — this file.

## Workflow

### 1. Capture from your source laptop (Arch/Omarchy)
```bash
bash capture.sh
```
Produces `mango-omarchy-capture/` containing `configs.tgz`, `mango.desktop`, `pkg-explicit.txt`, `pkg-aur.txt`, `provenance.txt`.

Upload `configs.tgz` (and `mango.desktop`) somewhere private reachable via URL (private GitHub repo, gist, or any file host).

### 2. On the fresh target machine (minimal TTY, network up)
Ensure a fetcher, then run:
```bash
source /etc/os-release
case $ID in
  arch)    sudo pacman -Sy --noconfirm curl ;;
  fedora)  sudo dnf install -y curl ;;
  debian)   sudo apt-get update && sudo apt-get install -y curl ;;
esac

curl -fsSL https://<your-repo>/bootstrap.sh -o ~/bootstrap.sh
bash ~/bootstrap.sh --config-url https://<your-private-url>/configs.tgz
```

Without `--config-url`, only the system layer (mango, ly, omarchy shell, apps) is installed and a warning is printed.

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

- **mango**: Arch via AUR (`mangowm-git`); Fedora/Debian built from source (pinned `wlroots 0.19.2` + `scenefx 0.4.1`).
- **ly**: Arch via repo; Fedora/Debian built from source (zig). Replaces SDDM/GDM/LightDM.
- **Omarchy shell**: cloned from the omarchy repo; `bin/` added to `PATH`. `quickshell` installed (AUR on Arch, best-effort source build elsewhere).
- **Omarchy CLI tools** (`omarchy-clipboard-universal`, `omarchy-capture-text`, etc.): shipped by the repo, made callable via `PATH`. Their runtime deps (`jq`, `wtype`, `slurp`, `grim`, `tesseract`, `wl-clipboard`, `cliphist`, `hyprpicker`, …) are installed.
- **Apps**: `foot`, `walker`, `starship`, `fastfetch`, `neovim`, `mpv`, `fzf`, `ripgrep`, and friends.

All package installs are idempotent: already-installed packages are skipped.

## Known limits

- `omarchy pkg add` / `omarchy update` and other pacman-bound helpers do not work off-Arch.
- `quickshell` source build on Fedora/Debian may fail; the script continues and the bar/menu simply won't appear (mango + apps still work).
- `wlroots` is pinned to `0.19.2`, which is why mango is built from source off-Arch.
- `hyprpicker` has no Fedora package, so it is built from source there.

## Verifying before a real run
```bash
bash bootstrap.sh --check
```
Reports, per distro, which packages are installed / available / missing and which source-built components are present.
