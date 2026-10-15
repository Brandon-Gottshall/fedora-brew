# Fedora Brew

Fedora Brew is a personal Homebrew tap and **Linux Application Catalog & Resolver** that bridges heterogeneous Linux application distributions (**RPM/DNF**, **Flatpak**, and **Homebrew Cellar Tarballs**) behind a clean, unified command:

```bash
brew app install <app>
brew app upgrade <app>
brew app uninstall <app>
```

*(You can also use the traditional `brew install <formula>` for standalone formula builds, or use `brew linux` as an alias).*

Current Homebrew-managed Linux applications include Claude Desktop, Google Antigravity,
Shadow PC, and Toshy. Toshy uses a separate checksummed runtime formula plus a cask that owns
only its user-level launchers and services.

---

## 🌟 Linux App Catalog & Backend Resolver (`brew app`)

Rather than forcing one fixed backend, `brew app` presents an interactive selection layer when multiple distribution methods exist:

```bash
$ brew app install antigravity

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

### Non-Interactive & Scripting Flags:
```bash
# Force native RPM / DNF backend
brew app install antigravity --rpm

# Force Flatpak backend
brew app install antigravity --flatpak

# Force Homebrew Cellar formula
brew app install antigravity --brew

# Set global preference
brew app config default_backend flatpak
```

See **[docs/APP_CATALOG.md](docs/APP_CATALOG.md)** for full documentation.

---

## Documentation & Contributor Guides

* **[Linux App Catalog & Resolver Guide](docs/APP_CATALOG.md)**: How `brew app` manages backends and manifest definitions.
* **[Package Admission & Ownership Policy](docs/ADMISSION_POLICY.md)**: Rules on when to package an app here vs DNF/Flatpak.
* **[Step-by-Step SOP for Adding Packages](docs/ADDING_A_PACKAGE.md)**: Complete playbook for researching, authoring, and testing new packages.
* **[Formula Patterns & Archetypes](docs/FORMULA_PATTERNS.md)**: Tested formula templates for Electron apps, AppImages, Debian (`.deb`) extractions, and standalone binaries.
* **[Desktop Integration Architecture](docs/DESKTOP_INTEGRATION.md)**: Deep dive into XDG discovery, KDE Plasma pre-startup hooks, and launcher indexing (Vicinae, KRunner, App Menu).
* **[Update Automation Guide](docs/UPDATE_AUTOMATION.md)**: Release scrapers, checksum pinning, and GitHub Actions PR workflows.
* **[Cross-Platform Setup & Brewfile Guide](docs/CROSS_PLATFORM_SETUP.md)**: 3-layer machine bootstrap architecture across Fedora and macOS.
* **[Case Study: Google Antigravity 2.x](docs/CASE_STUDY_ANTIGRAVITY.md)**: Comprehensive technical retrospective on adding Antigravity 2.x.
* **[Contributing Guidelines](CONTRIBUTING.md)**: PR checklist and testing instructions.

---

## Ownership Policy

* **DNF-managed packages** remain owned exclusively by DNF.
* **Flatpak applications** remain owned exclusively by Flatpak.
* **Fedora Brew applications** have their self-contained payload owned exclusively by Homebrew.

Formulas must never invoke `sudo dnf install`, `flatpak install`, or other external package managers. Uninstalling removes package-owned files only; user data, settings, credentials, and projects are always preserved.

---

## Quickstart & Desktop Bootstrap

Homebrew links formula assets under its own prefix. Linux desktop environments do not search that prefix by default, so configure it once:

```bash
# 1. Attach tap
brew tap Brandon-Gottshall/fedora-brew https://github.com/Brandon-Gottshall/fedora-brew

# 2. Trust tap commands
brew trust --tap Brandon-Gottshall/fedora-brew

# 3. Run desktop bootstrap once
"$(brew --prefix)/Homebrew/Library/Taps/brandon-gottshall/homebrew-fedora-brew/scripts/bootstrap-desktop"

# 4. Verify system health
"$(brew --prefix)/Homebrew/Library/Taps/brandon-gottshall/homebrew-fedora-brew/scripts/doctor"
```

The bootstrap script adds Homebrew's `share` directory to `XDG_DATA_DIRS`, refreshes desktop caches, and configures a Plasma pre-startup hook in `~/.config/plasma-workspace/env/`.

---

## Reference Package: Google Antigravity 2.x

### Product Boundary
Google Antigravity 2.0 is a standalone desktop agent command center, separate from the legacy 1.x IDE / RPM channel. The formula pins immutable Google Cloud Storage tarballs and calculates verifiable SHA-256 hashes.

### Installation
```bash
brew install Brandon-Gottshall/fedora-brew/antigravity
brew test Brandon-Gottshall/fedora-brew/antigravity
```

### Normal Lifecycle
```bash
brew upgrade antigravity
brew uninstall antigravity
```

## Claude Desktop

Install Anthropic's official Claude Desktop Linux beta on Fedora through the tap:

```bash
brew app install claude-desktop --brew
brew upgrade claude-desktop
```

The formula extracts Anthropic's checksummed Debian payload without running its
APT maintainer scripts, leaving Homebrew as the sole update owner. Fedora is not
currently an upstream-supported distribution.

## Shadow PC and Toshy

Install Shadow PC directly or through the catalog:

```bash
brew install Brandon-Gottshall/fedora-brew/shadow-pc
brew app install shadow-pc --brew
```

Before moving an existing loose AppImage, verify the migration without writes:

```bash
scripts/migrate-shadow-pc --dry-run --source "$HOME/Downloads/ShadowPC.appimage"
```

Toshy requires the runtime formula and cask. Existing installations must pass the
non-writing component, input-access, runtime, backup, and service-manager checks:

```bash
brew install Brandon-Gottshall/fedora-brew/toshy-runtime
toshy-brew-sync migrate
brew install --cask Brandon-Gottshall/fedora-brew/toshy
toshy-brew-doctor
```

`migrate` is always a dry run. The cask performs the real integration only after
the same preflight succeeds. Normal uninstall preserves Toshy configuration and
rollback snapshots; `brew uninstall --zap --cask toshy` is the explicit cleanup.

---

## Validation Suite

Run repository tests before submitting contributions:

```bash
python3 -m unittest discover -s test -p 'test_*.py'
bash test/test_desktop_bootstrap.sh
bash test/test_formula.sh
bash test/test_migration.sh
bash test/test_doctor.sh
bash test/test_app_manager.sh
bash test/test_shadow_pc.sh
bash test/test_claude_desktop.sh
brew ruby -- -c Formula/antigravity.rb
brew ruby -- -c Formula/claude-desktop.rb
brew ruby -- -c Formula/shadow-pc.rb
brew ruby -- -c Formula/toshy-runtime.rb
brew ruby -- -c Casks/toshy.rb
bash -n scripts/bootstrap-desktop scripts/migrate-antigravity-v1-fedora scripts/migrate-shadow-pc scripts/doctor scripts/brew-app
brew audit --strict Brandon-Gottshall/fedora-brew/antigravity
brew audit --strict Brandon-Gottshall/fedora-brew/claude-desktop
brew audit --strict Brandon-Gottshall/fedora-brew/shadow-pc
brew audit --strict Brandon-Gottshall/fedora-brew/toshy-runtime
brew audit --cask --strict Brandon-Gottshall/fedora-brew/toshy
```
