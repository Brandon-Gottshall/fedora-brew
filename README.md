# Fedora Brew

Fedora Brew is a personal Homebrew tap that adapts heterogeneous, self-contained Linux application artifacts into one consistent lifecycle:

```bash
brew install <app>
brew upgrade <app>
brew uninstall <app>
```

Use a native system package manager when upstream provides a good native package. Use this tap when an upstream Linux application does not provide an acceptable package-management lifecycle.

The repository is named for its first host environment, but its packaging conventions are not Fedora-specific. Future formulas may adapt AppImages, archives, standalone binaries, vendor downloads, `.deb` payloads, or source builds without changing the repository structure. No generalized package DSL is planned.

**Google Antigravity 2.x is currently the only supported and reference package.**

## Ownership policy

- DNF-managed packages remain owned by DNF.
- Flatpak applications remain owned by Flatpak.
- Applications admitted to this tap have their self-contained payload owned by Homebrew.

Formulas must not invoke `sudo dnf install`, `flatpak install`, or another package manager and then claim ownership. Normal uninstall removes package-owned files only; projects, credentials, preferences, caches, and other user data are preserved.

## Bootstrap

Homebrew links formula assets under its own prefix. Linux desktops do not search that prefix by default, so configure it once:

```bash
git clone https://github.com/Brandon-Gottshall/fedora-brew.git
cd fedora-brew
scripts/bootstrap-desktop
brew tap Brandon-Gottshall/fedora-brew https://github.com/Brandon-Gottshall/fedora-brew
```

The bootstrap adds Homebrew's `share` directory to `XDG_DATA_DIRS`, refreshes desktop caches when available, and writes no application-specific files. A new login makes the environment persistent for every process. It can be reversed with `scripts/bootstrap-desktop --remove`.

## Antigravity 2.x

### Product boundary

Google Antigravity 2.0 is a standalone desktop agent command center. It is separate from the older Antigravity IDE.

The official general download page currently publishes:

- version: `2.8.1`
- build: `6512087774658560`
- architecture: Linux x86_64
- artifact: `Antigravity.tar.gz`
- SHA-256: `23f6c3bfef2b3326f8b747cd9e15ba3401c702280436e4e03b9a863c6678eff3`

The legacy Linux page still links version `1.23.2` and an RPM repository configured with `gpgcheck=0`. Neither is used by this formula. Version 1.x artifacts are rejected by update tooling.

Google does not publish a checksum alongside the 2.x tarball. The formula therefore pins a SHA-256 calculated from Google's immutable HTTPS object. The trust boundary is Google Storage plus review of an automated update pull request.

Sources:

- [Antigravity 2.0 download page](https://antigravity.google/download)
- [Antigravity 2.0 documentation](https://antigravity.google/docs/getting-started)
- [Antigravity changelog](https://antigravity.google/changelog)
- [Antigravity 2.0 announcement](https://antigravity.google/blog/introducing-google-antigravity-2)
- [Legacy Linux page, documented for exclusion](https://antigravity.google/download/linux)

### Migrate from legacy Fedora RPM

Inspect first; dry-run is the default:

```bash
scripts/migrate-antigravity-v1-fedora
```

Apply only the reported legacy removal:

```bash
scripts/migrate-antigravity-v1-fedora --apply
```

The script:

1. queries the exact RPM package named `antigravity`;
2. reports the RPM owning any current `antigravity` command;
3. matches only the `[antigravity-rpm]` repository or the exact legacy Google Artifact Registry URL;
4. reports but preserves unrelated Google repositories;
5. removes the exact legacy package and dedicated repository;
6. refreshes DNF metadata; and
7. verifies that RPM/DNF ownership and the repository relationship are gone.

It fails closed when command ownership is ambiguous.

### Install and use

```bash
brew install Brandon-Gottshall/fedora-brew/antigravity
brew test Brandon-Gottshall/fedora-brew/antigravity
```

After bootstrap, Google Antigravity appears in KDE Application Launcher and KRunner. The desktop entry uses stable Homebrew `opt` paths, so upgrades do not leave versioned Cellar paths or duplicate launchers.

Normal lifecycle:

```bash
brew upgrade antigravity
brew uninstall antigravity
```

The formula disables Antigravity's built-in updater so Homebrew remains the only application lifecycle owner.

## Updating

The formula has Homebrew `livecheck` metadata. `scripts/update-formula.py` independently enforces the 2.x product boundary:

```bash
scripts/update-formula.py --check
scripts/update-formula.py
```

It requires exactly one official `antigravity-hub/<2.x-version>-<build>/linux-x64/Antigravity.tar.gz` URL. It refuses legacy, malformed, or ambiguous pages. When a new version is found, it downloads the immutable object, calculates SHA-256, and changes only the formula URL, version, and checksum.

The scheduled GitHub Action runs this process and opens or updates a pull request after tests and audit; it never commits an unvalidated release directly to `main`.

## Formula conventions

Future formulas should:

1. use an official immutable HTTPS artifact and a pinned checksum;
2. restrict untested operating systems and architectures explicitly;
3. validate expected payload shape before installation;
4. install the complete self-contained payload in the Cellar;
5. expose launchers through stable `opt` paths;
6. install desktop entries and icons below `share/`;
7. disable upstream self-update when Homebrew owns upgrades;
8. keep user state outside package cleanup; and
9. provide strict, testable release discovery before adding automation.

## Validation

Repository checks:

```bash
python3 -m unittest discover -s test -p 'test_*.py'
bash test/test_formula.sh
bash test/test_migration.sh
brew ruby -- -c Formula/antigravity.rb
bash -n scripts/bootstrap-desktop scripts/migrate-antigravity-v1-fedora
brew audit --strict Brandon-Gottshall/fedora-brew/antigravity
```

Lifecycle validation additionally checks install, `brew test`, command resolution, desktop-file validity, stable `Exec=`, uninstall, reinstall, and legacy DNF absence.
