# Linux Application Catalog & Multi-Backend Resolver (`brew app` / `brew-linux`)

This document explains the architecture and usage of `brew app` (aliased as `brew linux`), which transforms Homebrew into a unified **application catalog and resolver** for Linux.

---

## 1. The Core Concept: The App Store Protocol for Linux

On modern Linux desktops, software distribution is fragmented across multiple formats:
* Native RPM/DNF repositories
* COPR repositories
* Flatpaks (Flathub)
* Self-contained vendor tarballs and Electron binaries (Homebrew Cellar)
* AppImages

Users frequently ask: *"I want application X, but I care about how it integrates with my machine."*

Instead of forcing a single backend or trying to make Flatpak and RPM look like identical Homebrew packages inside the Cellar, `fedora-brew` implements a **selection and resolution layer**:

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
* **DNF / Flatpak / Homebrew**: Act as the respective execution engines.

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
     • [Pro] Integrated with fedora-brew update automation
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

# Preview commands without executing
brew app install antigravity --flatpak --dry-run
```

---

## 4. Package Manifest Format (`packages/*.yaml`)

Every application in the catalog is defined by a simple, declarative YAML manifest in `packages/`:

```yaml
name: antigravity
display_name: Google Antigravity
description: Standalone command center for Google Antigravity agents
homepage: https://antigravity.google/product/antigravity-2

default: rpm

backends:
  rpm:
    summary: Native Fedora RPM package (via official repository)
    pros:
      - Native desktop menu and system notification integration
      - Automatic updates managed through system dnf
    cons:
      - Requires sudo privileges to add repository and install
    repo:
      name: antigravity-rpm
      baseurl: https://us-central1-yum.pkg.dev/projects/antigravity-hub/antigravity-rpm
      gpgcheck: 0
    package: antigravity

  flatpak:
    summary: Sandboxed Flatpak package
    pros:
      - Sandboxed isolation from host filesystem
      - Same consistent runtime across all Linux distributions
    cons:
      - Larger initial download due to runtime dependencies
    remote: flathub
    app_id: com.google.Antigravity

  brew:
    summary: Homebrew Cellar Standalone formula (Tarball payload)
    pros:
      - Installs entirely in user space without sudo
      - Pinned SHA-256 immutable download with strict lifecycle tracking
      - Integrated with fedora-brew update automation
    cons:
      - Links against host system GUI libraries
    formula: Brandon-Gottshall/fedora-brew/antigravity
```

### Supported Backend Types:
* **RPM**:
  * Direct packages: `package: <pkg_name>`
  * Dedicated repos: `repo: { name: ..., baseurl: ..., gpgcheck: ... }`
  * COPR repositories: `copr: <user>/<project>`
* **Flatpak**:
  * Flathub applications: `app_id: <id>`, `remote: flathub`
* **Homebrew**:
  * Tap formulas: `formula: <tap>/<formula>`

---

## 5. State Tracking & Preferences

`brew app` tracks application state in `~/.config/fedora-brew/`:

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

## 6. Command Reference

| Command | Description |
| :--- | :--- |
| `brew app install <pkg> [flags]` | Install application with backend choice. |
| `brew app upgrade [pkg]` | Upgrade specified application or all managed applications. |
| `brew app uninstall <pkg>` | Cleanly uninstall application via its active backend. |
| `brew app list` | List all managed applications and catalog packages. |
| `brew app info <pkg>` | View full package details, descriptions, and backend matrix. |
| `brew app config [key] [value]` | View or update global preferences. |
| `brew app doctor` | Run system integration diagnostics. |
