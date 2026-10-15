# Linux Formulas

Linux Formulas is a personal Homebrew tap and **Linux Application Catalog & Resolver** that bridges heterogeneous Linux application distributions (**RPM/DNF**, **pacman/AUR**, **Flatpak**, and **Homebrew**) behind a clean, unified command:

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
     • [Pro] Integrated with linux-formulas update automation
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
* **Linux Formulas applications** have their self-contained payload owned exclusively by Homebrew.

Formulas must never invoke `sudo dnf install`, `flatpak install`, or other external package managers. Uninstalling removes package-owned files only; user data, settings, credentials, and projects are always preserved.

---

## Quickstart & Desktop Bootstrap

Homebrew links formula assets under its own prefix. Linux desktop environments do not search that prefix by default, so configure it once:

```bash
# 1. Attach tap
brew tap Brandon-Gottshall/linux-formulas https://github.com/Brandon-Gottshall/fedora-brew

# 2. Trust tap commands
brew trust --tap Brandon-Gottshall/linux-formulas

# 3. Run desktop bootstrap once
"$(brew --prefix)/Homebrew/Library/Taps/brandon-gottshall/homebrew-linux-formulas/scripts/bootstrap-desktop"

# 4. Verify system health
"$(brew --prefix)/Homebrew/Library/Taps/brandon-gottshall/homebrew-linux-formulas/scripts/doctor"
```

The bootstrap script adds Homebrew's `share` directory to `XDG_DATA_DIRS`, refreshes desktop caches, and configures a Plasma pre-startup hook in `~/.config/plasma-workspace/env/`.

---

## Reference Package: Google Antigravity 2.x

### Product Boundary
Google Antigravity 2.0 is a standalone desktop agent command center, separate from the legacy 1.x IDE / RPM channel. The formula pins immutable Google Cloud Storage tarballs and calculates verifiable SHA-256 hashes.

### Installation
```bash
brew install Brandon-Gottshall/linux-formulas/antigravity
brew test Brandon-Gottshall/linux-formulas/antigravity
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

## Jump Desktop: experimental Linux wrapper

**WARNING: The Linux `jump-desktop` formula is an unsupported, third-party
Electron web wrapper. It is not the official Jump Desktop application or a
native Linux RDP, VNC, or Fluid client. Do not rely on it for critical remote
access.** Features and authentication depend on the hosted Jump Desktop web
client and can break without notice. Keyboard and gesture forwarding is best
effort; desktop shortcuts can still interfere. The wrapper can modify user KWin
rules to capture shortcuts, and its external sign-in flow can import browser
session credentials. Treat the wrapper and its local profile as sensitive.

The wrapper pins its Electron runtime; it does not receive automatic Electron
security updates. Review runtime updates before using it with sensitive accounts.
Session cookies and settings remain in `~/.config/jump-desktop/` after uninstall.

Use an explicit formula selection on Linux, because Homebrew's official macOS
cask also uses the `jump-desktop` token:

```bash
brew install --formula Brandon-Gottshall/linux-formulas/jump-desktop
# Or use the catalog's explicit formula backend:
brew app install jump-desktop --brew
```

The tap's official macOS application cask is now `jump-desktop-mac`:

```bash
brew install --cask Brandon-Gottshall/linux-formulas/jump-desktop-mac
```

`cask_renames.json` maps this tap's previous `jump-desktop` cask token to
`jump-desktop-mac` for Homebrew migration. The Linux formula keeps its name.
No cross-tap migration is needed for this cask rename.

## Shadow PC and Toshy

Install Shadow PC directly or through the catalog:

```bash
brew install Brandon-Gottshall/linux-formulas/shadow-pc
brew app install shadow-pc --brew
```

Before moving an existing loose AppImage, verify the migration without writes:

```bash
scripts/migrate-shadow-pc --dry-run --source "$HOME/Downloads/ShadowPC.appimage"
```

Toshy requires the runtime formula and cask. Existing installations must pass the
non-writing component, input-access, runtime, backup, and service-manager checks:

```bash
brew install Brandon-Gottshall/linux-formulas/toshy-runtime
toshy-brew-sync migrate
brew install --cask Brandon-Gottshall/linux-formulas/toshy
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
brew audit --strict Brandon-Gottshall/linux-formulas/antigravity
brew audit --strict Brandon-Gottshall/linux-formulas/claude-desktop
brew audit --strict Brandon-Gottshall/linux-formulas/shadow-pc
brew audit --strict Brandon-Gottshall/linux-formulas/toshy-runtime
brew audit --cask --strict Brandon-Gottshall/linux-formulas/toshy
```

## Migrating from fedora-brew

The tap identity is now `Brandon-Gottshall/linux-formulas`. Until the GitHub
repository itself is renamed, use the existing repository URL explicitly:

```bash
brew tap Brandon-Gottshall/linux-formulas https://github.com/Brandon-Gottshall/fedora-brew
brew trust --tap Brandon-Gottshall/linux-formulas
```

After the repository rename, `brew tap Brandon-Gottshall/linux-formulas` works
without a custom URL. Update Brewfiles and scripts to the new tap identity.
Keep the old tap until packages installed from it have been moved. For each
installed formula, reinstall using the new fully qualified name, verify it,
then remove the old tap once no installed packages depend on it. Back up
application data before any reinstall. Avoid force-untapping installed packages.

The app manager copies `config.json` and `installed.json` from
`~/.config/fedora-brew` into `~/.config/linux-formulas` on first use, only if
the new directory does not exist. The original files are preserved. An existing
new directory is never overwritten. `XDG_CONFIG_HOME` is honored.
`LINUX_FORMULAS_CONFIG_DIR` and `HOMEBREW_LINUX_FORMULAS_CONFIG_DIR` are the new
path overrides; the old `FEDORA_BREW_CONFIG_DIR` and
`HOMEBREW_FEDORA_BREW_CONFIG_DIR` remain supported with lower priority.

The old macOS cask token maps to `jump-desktop-mac` through
`cask_renames.json`; the Linux formula remains `jump-desktop`. Use the explicit
formula command above to avoid Homebrew's official macOS cask collision.

On Arch/CachyOS, `--native` selects pacman. AUR installs use an existing `paru`
or `yay`, or a pacman-compatible executable selected with
`LINUX_FORMULAS_AUR_HELPER` / `brew app config aur_helper /path/to/helper`.
The manager does not install an AUR helper. Native Arch installs run a full
synchronized upgrade (`-Syu`) to avoid unsupported partial upgrades.

Fedora container validation is deferred to a separate PR. The CI additions here
cover portable tooling on Ubuntu/macOS and package installation on CachyOS.
