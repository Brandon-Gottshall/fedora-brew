# Linux Application Catalog & Multi-Backend Resolver (`brew app` / `brew-linux`)

This document explains the architecture and usage of `brew app` (aliased as `brew linux`), which transforms Homebrew into a unified **application catalog and resolver** for Linux.

---

## 1. The Core Concept: The App Store Protocol for Linux

On modern Linux desktops, software distribution is fragmented across multiple formats:
* Native RPM/DNF and Arch pacman repositories
* AUR packages through an installed helper
* COPR repositories
* Flatpaks (Flathub)
* Self-contained vendor tarballs and Electron binaries (Homebrew Cellar)
* AppImages

Users frequently ask: *"I want application X, but I care about how it integrates with my machine."*

Instead of forcing a single backend or trying to make Flatpak and RPM look like identical Homebrew packages inside the Cellar, `linux-formulas` implements a **selection and resolution layer**:

```
┌────────────────────────────────────────────────────────┐
│                      User Request                      │
│               brew app install antigravity             │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│             Package Manifest Resolver                  │
│             (packages/antigravity.yaml)                │
└──────────────────────────┬─────────────────────────────┘
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
      ┌────────────┐ ┌───────────┐ ┌───────────┐
      │    RPM     │ │  Flatpak  │ │ Homebrew  │
      │  (Native)  │ │(Sandboxed)│ │ (Cellar)  │
      └─────┬──────┘ └─────┬─────┘ └─────┬─────┘
            ▼              ▼             ▼
        sudo dnf        flatpak        brew
```

* **Homebrew**: Acts as the catalog, metadata index, and resolver.
* **DNF / pacman / AUR helper / Flatpak / Homebrew**: Act as the respective execution engines.

---

## 2. Interactive Selection in Terminal (TTY)

When running interactively without explicit backend flags:
```bash
brew app install antigravity
```

The resolver displays the available backends with summaries, pros, and cons:

```text
Google Antigravity has multiple Linux backends available:

  1) RPM (recommended/default)
     Summary: Native Fedora RPM package (via official repository)
     • [Pro] Native desktop menu and system notification integration
     • [Pro] Automatic updates managed through system dnf
     • [Con] Requires sudo privileges to add repository and install

  2) FLATPAK
     Summary: Sandboxed Flatpak package
     • [Pro] Sandboxed isolation from host filesystem
     • [Pro] Same consistent runtime across all Linux distributions
     • [Con] Larger initial download due to runtime dependencies

  3) BREW
     Summary: Homebrew Cellar Standalone formula (Tarball payload)
     • [Pro] Installs entirely in user space without sudo
     • [Pro] Pinned SHA-256 immutable download with strict lifecycle tracking
     • [Pro] Integrated with linux-formulas update automation
     • [Con] Links against host system GUI libraries

Choose installation method [1-3] (default: 1):
```

Pressing **Enter** chooses the recommended default; entering `1`, `2`, or `3` (or typing `flatpak`, `rpm`, `brew`) selects the corresponding backend.

---

## 3. Non-Interactive Scripting & Explicit Flags

For setup scripts, CI workflows, and Brewfiles, you can bypass the prompt with explicit flags:

```bash
# Force native RPM backend (via DNF)
brew app install antigravity --rpm
brew app install antigravity --native

# Force Flatpak backend (via Flathub)
brew app install antigravity --flatpak

# Force Homebrew standalone formula (Cellar)
brew app install antigravity --brew
brew app install antigravity --tarball

# Release AppImage / archive (manifest URL or latest GitHub release)
brew app install moonlight-qt --appimage
brew app install ripgrep --archive

# Preview commands without executing
brew app install antigravity --flatpak --dry-run
```

---

## 4. Installing Names Outside the Catalog

`brew app install <name>` resolves a name in this order:

1. **Catalog**: a manifest named `<name>`, or one listing it under `aliases` (`claude` → `claude-code`). The manifest's own backend choice applies.
2. **Homebrew**: a formula, or a cask that installs on Linux, named exactly `<name>`. It installs normally and Homebrew keeps it updated.
3. **Discovery**: exact matches on Flathub, the pacman repositories and the AUR, in that order. A GitHub release AppImage, then a release archive (`.tar.gz`, `.tar.xz`, …), is offered only when nothing earlier matched. Matches are listed with their source details and installed only after you confirm (`-y` accepts the first).

Discovered installs are recorded with the definition they were installed from, so `brew app upgrade` keeps them current like catalog apps. AppImages and archives install under `~/.local/share/linux-formulas/apps/<name>` with the executable linked into `~/.local/bin`. They are checked against GitHub's published SHA-256 digest when the release provides one. Upgrades move to the newest release, and existing files in `~/.local/bin` that the tap didn't create are never overwritten.

Manifests can use the release backends too, either pinned or tracking a repository:

```yaml
backends:
  appimage:
    url: https://example.com/Tool-1.2.AppImage
    sha256: <sha256>
  archive:
    github: owner/tool
    asset: linux-x86_64\.tar\.gz$   # optional regex narrowing the release asset
    binary: tool                      # optional executable name inside the archive
```

### One `brew` for everything

`brew app` reads every package manager live: Homebrew, pacman and the AUR (Arch), DNF (Fedora), Flatpak, and the tap's AppImage and archive installs. It doesn't rely on its own records, so packages installed with pacman, an AUR helper, Shelly or `flatpak` are covered as soon as they exist.

| Command | What it does |
|---|---|
| `brew app list` | Installed packages from every manager, grouped by source (explicitly installed ones; dependencies are left out) |
| `brew app outdated` | Pending updates from every manager (`brew outdated`, `checkupdates`, `yay -Qua`, `dnf check-update`, `flatpak remote-ls --updates`, newer GitHub releases) |
| `brew app upgrade` | Homebrew, then the whole system in one transaction (`yay -Syu` / `pacman -Syu` on Arch, `dnf upgrade --refresh` on Fedora), then Flatpak apps and runtimes, then release apps. Every step runs even if an earlier one fails |
| `brew app upgrade <name>` | Upgrades through whichever manager owns `<name>`. On Arch that is a full system upgrade, since partial upgrades aren't supported |
| `brew app uninstall <name>` | Removes through the owning manager (`pacman -Rs`, `flatpak uninstall`, `brew uninstall`, …) |
| `brew app info <name>` / `brew app search <text>` | Details from the owning manager, or results from the catalog, Homebrew, Flathub, the repositories and the AUR together |

Fedora major-version upgrades (`dnf system-upgrade`) need a reboot, so they stay manual.

`scripts/shell/brew.bash` makes these the plain `brew` commands in your interactive shell. Source it from your profile:

```bash
. "$(brew --repository brandon-gottshall/fedora-brew)/scripts/shell/brew.bash"
```

`brew install|upgrade|uninstall|list|outdated|info|search` then go through `brew app`. Tap-qualified names (`owner/tap/name`), Homebrew-only options (`--cask`, `--greedy`, `--json`, …), `brew list <formula>` and every other subcommand still go to Homebrew unchanged. Scripts that call `brew` never load the wrapper.

---

## 5. Package Manifest Format (`packages/*.yaml`)

Every application in the catalog is defined by a simple, declarative YAML manifest in `packages/`:

```yaml
name: example
display_name: Example
homepage: https://example.org
default: brew
backends:
  brew:
    formula: Brandon-Gottshall/linux-formulas/example
  flatpak:
    remote: flathub
    app_id: org.example.Example
macos:
  default: brew
  backends:
    brew:
      cask: Brandon-Gottshall/linux-formulas/example-mac
distros:
  fedora:
    default: rpm
    backends:
      rpm:
        package: example
  arch:
    default: pacman
    backends:
      pacman:
        package: example
      aur:
        package: example-git
```

`backends` contains methods shared by Linux distributions. The matching
`distros` section adds native methods; `macos` supplies the macOS methods.
Linux distribution selection reads `ID` and `ID_LIKE` from `/etc/os-release`,
so CachyOS selects the Arch family. Only backends for the current platform
are offered, including when an explicit flag is supplied.

Native RPM definitions accept `package`, optional `copr`, and optional `repo`
metadata. Pacman and AUR definitions accept `package`; AUR uses an installed
helper rather than installing one. Use `--pacman`, `--aur`, `--rpm`, `--flatpak`,
or `--brew` to select explicitly. `--native` resolves to RPM on Fedora and
pacman on Arch. Homebrew definitions use `formula` or `cask`; Linux casks such
as Toshy stay in shared Linux backends.

---

## 6. State Tracking & Preferences

`brew app` tracks application state in `~/.config/linux-formulas/`:

* **`installed.json`**: Records which backend installed each application so `upgrade` and `uninstall` automatically dispatch to the correct engine without re-prompting.
* **`config.json`**: Global preferences.

### Configuring Global Defaults:
```bash
# Prefer Flatpak globally when no flag is provided
brew app config default_backend flatpak

# Prefer RPM globally
brew app config default_backend rpm

# View current configuration
brew app config
```

---

## 7. Command Reference

| Command | Description |
| :--- | :--- |
| `brew app install <pkg> [flags]` | Install application with backend choice. |
| `brew app upgrade [pkg]` | Upgrade specified application or all managed applications. |
| `brew app uninstall <pkg>` | Cleanly uninstall application via its active backend. |
| `brew app list` | List all managed applications and catalog packages. |
| `brew app info <pkg>` | View full package details, descriptions, and backend matrix. |
| `brew app config [key] [value]` | View or update global preferences. |
| `brew app doctor` | Run system integration diagnostics. |
