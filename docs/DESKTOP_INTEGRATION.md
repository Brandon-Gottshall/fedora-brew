# Desktop Integration Architecture

This document explains how `fedora-brew` bridges Homebrew-installed desktop applications and icons to Linux desktop environments (KDE Plasma, GNOME, XFCE) and application launchers (KRunner, Vicinae, Application Menu).

---

## 1. The Core Challenge

By default, Linux desktop standards specify that application launchers and file managers look for `.desktop` and icon files in directories defined by the `$XDG_DATA_DIRS` environment variable.

On standard Fedora installations, `$XDG_DATA_DIRS` contains:
```bash
/home/<user>/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share
```

When Homebrew installs a formula with a desktop entry or icon, it writes to:
```bash
/home/linuxbrew/.linuxbrew/share/applications/
/home/linuxbrew/.linuxbrew/share/icons/
```

Because Homebrew's prefix is not in the system `$XDG_DATA_DIRS`, launchers cannot find Homebrew applications unless the environment is properly configured.

---

## 2. The Solution Architecture

To integrate Homebrew without modifying system-wide protected files in `/etc` or `/usr`, `scripts/bootstrap-desktop` sets up a dual-layer user configuration:

```
┌────────────────────────────────────────────────────────┐
│               scripts/bootstrap-desktop                │
└──────────────────────────┬─────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
 ┌──────────────────────┐    ┌──────────────────────┐
 │    environment.d     │    │   plasma-workspace   │
 │ 60-fedora-brew.conf  │    │ 60-fedora-brew.sh    │
 └──────────┬───────────┘    └──────────┬───────────┘
            │                           │
            ▼                           ▼
  Systemd User Services        KDE Plasma Pre-Startup
  (Generic Fallback)           (Sources before Autostart)
            │                           │
            └─────────────┬─────────────┘
                          │
                          ▼
            ┌───────────────────────────┐
            │   XDG_DATA_DIRS updated   │
            │   Homebrew /share linked  │
            └─────────────┬─────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
  KDE App Menu         KRunner          Vicinae
```

### Layer 1: KDE Plasma Pre-Startup Hook
* **File Location**: `~/.config/plasma-workspace/env/60-fedora-brew-xdg-data.sh`
* **Mechanism**: Plasma sources all executable `.sh` scripts in `plasma-workspace/env/` *prior* to launching the desktop shell and any user autostart applications.
* **Why this is necessary**: Fedora's display manager initialization often overrides or clears standard `environment.d` variables during login. The Plasma hook ensures Homebrew's share directory is always prepended to `XDG_DATA_DIRS`.

### Layer 2: Generic `environment.d` Configuration
* **File Location**: `~/.config/environment.d/60-fedora-brew-xdg-data.conf`
* **Mechanism**: Read by systemd user managers and compatible desktop environments (GNOME, Sway, etc.) at user login.

### Layer 3: Dynamic Cache & Environment Notification
During execution, `scripts/bootstrap-desktop` also:
1. Runs `systemctl --user set-environment XDG_DATA_DIRS=...` for newly launched user services.
2. Updates DBus environment with `dbus-update-activation-environment`.
3. Runs `update-desktop-database` on Homebrew's `share/applications`.
4. Refreshes KDE sycoca cache using `kbuildsycoca6`.

---

## 3. Stability Rules for Bootstrap Scripts

1. **Never Restart Graphical Shells**: Do not execute `plasmashell --replace`, `kquitapp`, or kill compositor processes. Doing so causes open terminals (like Warp) and user windows to crash.
2. **Idempotence**: Sourcing or running the script multiple times will never duplicate entries in `XDG_DATA_DIRS`.
3. **Safe Uninstallation**: Running `scripts/bootstrap-desktop --remove` removes only files tagged with `# Managed by fedora-brew bootstrap.` and restores clean baseline paths.

---

## 4. Verification and Troubleshooting

### Verifying XDG_DATA_DIRS
Check if Homebrew share is active in your current session:
```bash
echo "$XDG_DATA_DIRS" | tr ':' '\n'
```
Expected output includes:
```
/home/linuxbrew/.linuxbrew/share
```

### Refreshing Application Launchers
* **KDE Application Menu / KRunner**: Rebuilds instantly with `kbuildsycoca6 --noincremental`.
* **Vicinae**: Run command `core:refresh-apps` or restart Vicinae if launched prior to bootstrap.
* **GNOME Shell**: Press `Alt+F2`, type `r`, and press Enter (on X11) or log out and log back in (on Wayland).
