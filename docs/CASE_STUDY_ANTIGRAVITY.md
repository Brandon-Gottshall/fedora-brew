# Case Study: Adding Google Antigravity 2.x to Linux Formulas

This document records the end-to-end design, implementation decisions, and troubleshooting journey that established **Google Antigravity 2.x** as the founding reference package in `linux-formulas`.

---

## 1. Context and Upstream Product Boundary

When adding Google Antigravity to the tap, the first challenge was resolving the upstream product identity and packaging channels:

### 1.1 The Product Boundary
Google Antigravity 2.0 is a standalone desktop agent command center, distinct from:
* The legacy Antigravity 1.x IDE.
* The Antigravity CLI and Python SDK.
* The legacy Antigravity 1.x RPM / repository channel.

### 1.2 Excluding the Legacy 1.x Channel
The legacy Linux download page (`https://antigravity.google/download/linux`) still distributes version `1.23.2` via an RPM repository configured with `gpgcheck=0`. This channel was deliberately excluded:
* It does not distribute the 2.x agent command center.
* Its packaging scripts interfere with system repository configuration.
* Its RPM payload conflicts with Homebrew-owned lifecycle management.

### 1.3 Upstream 2.x Artifact Discovery
The official 2.0 download portal (`https://antigravity.google/download`) publishes an immutable Google Cloud Storage tarball:
* **Canonical URL Format**: `https://storage.googleapis.com/antigravity-public/antigravity-hub/<version>-<build>/linux-x64/Antigravity.tar.gz`
* **Current Version**: `2.8.1` (Build `6512087774658560`)
* **Payload Type**: Electron application bundled for Linux x86_64.
* **Compressed Size**: ~163–171 MB; **Installed Size**: ~518 MB.

---

## 2. Integrity and Checksum Strategy

Because Google does not publish standalone `.sha256` or GPG signature files alongside the 2.x download:
1. **Immutable URL Pinning**: The formula pins the exact immutable GCS URL containing both the semantic version and build ID.
2. **SHA-256 Validation**: The SHA-256 hash (`23f6c3bfef2b3326f8b747cd9e15ba3401c702280436e4e03b9a863c6678eff3`) is calculated from this immutable object and pinned in the formula.
3. **No Insecure Bypasses**: Strict checksum verification remains enforced during `brew install` and `brew upgrade`.
4. **Automated Review Boundary**: Updates pass through automated GitHub Actions pull requests where maintainers review the upstream source change and SHA-256 recalculation.

---

## 3. Formula Architecture (`Formula/antigravity.rb`)

The formula encapsulates the full lifecycle of the self-contained Electron payload:

```ruby
class Antigravity < Formula
  desc "Standalone command center for Google Antigravity agents"
  homepage "https://antigravity.google/product/antigravity-2"
  url "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/linux-x64/Antigravity.tar.gz"
  sha256 "23f6c3bfef2b3326f8b747cd9e15ba3401c702280436e4e03b9a863c6678eff3"
  license :cannot_represent

  livecheck do
    url "https://antigravity.google/download"
    regex(%r{href=.*?/antigravity-hub/v?(\d+(?:\.\d+)+)-\d+/linux-x64/Antigravity\.t}i)
  end

  depends_on arch: :x86_64
  depends_on :linux

  resource "icon" do
    url "https://antigravity.google/assets/image/antigravity-logo.png"
    sha256 "8f0b95d2d21dbf930b4d100e2fdc4505673e900a731aa56ea633a4b59c312799"
  end

  def install
    wrapped_payload = buildpath/"Antigravity-x64"
    payload = wrapped_payload.directory? ? wrapped_payload : buildpath
    odie "Expected Antigravity 2.x executable is missing" unless (payload/"antigravity").executable?
    odie "Unexpected legacy Antigravity artifact" unless (payload/"resources/app-update.yml").exist?

    libexec.install payload.children
    (bin/"antigravity").write_env_script libexec/"antigravity", DISABLE_AUTO_UPDATE: "1"

    resource("icon").stage do
      (share/"icons/hicolor/256x256/apps").install "antigravity-logo.png" => "google-antigravity.png"
    end

    (share/"applications/google-antigravity.desktop").write <<~DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Google Antigravity
      GenericName=Agent Command Center
      Comment=Launch, monitor, and orchestrate Google Antigravity agents
      TryExec=#{opt_bin}/antigravity
      Exec=#{opt_bin}/antigravity %U
      Icon=google-antigravity
      Terminal=false
      StartupNotify=true
      StartupWMClass=Antigravity
      Categories=Development;
    DESKTOP
  end

  def caveats
    <<~EOS
      Desktop discovery uses Homebrew's share directory. Run the tap bootstrap once:
        #{tap.path}/scripts/bootstrap-desktop

      Antigravity's built-in updater is disabled so Homebrew remains the lifecycle owner.
    EOS
  end

  test do
    assert_predicate libexec/"antigravity", :executable?
    assert_path_exists libexec/"resources/app.asar"
    assert_path_exists share/"icons/hicolor/256x256/apps/google-antigravity.png"

    desktop = share/"applications/google-antigravity.desktop"
    assert_match "Exec=#{opt_bin}/antigravity %U", desktop.read
    assert_match "DISABLE_AUTO_UPDATE", (bin/"antigravity").read
  end
end
```

### Key Formula Design Decisions:

1. **Payload Isolation in `libexec`**:
   The entire Electron directory (binaries, `.asar` files, node modules, v8 snapshots) is placed in `libexec`, keeping Homebrew's top-level `bin` clean.

2. **Disabling Built-in Auto-Update**:
   Electron applications often attempt self-replacement when configured with an auto-updater. The wrapper script injected at `bin/antigravity` sets `DISABLE_AUTO_UPDATE=1`, preventing the application from breaking Homebrew's ownership of the files in Cellar.

3. **Stable `opt_bin` in Desktop Entry**:
   The `.desktop` file uses `#{opt_bin}/antigravity` rather than a versioned Cellar path (`/home/linuxbrew/.linuxbrew/Cellar/antigravity/2.8.1/...`). When Antigravity upgrades to a new version, the desktop entry never breaks and does not need to be rewritten.

4. **Static Test Suite**:
   Running GUI binaries in headless CI or `brew test` environments (e.g. `antigravity --version`) can launch an interactive window or crash without a display server. The formula test validates executable presence, critical resource bundles (`app.asar`), icon presence, wrapper environment flags, and `.desktop` structure without spawning GUI processes.

5. **Understanding `brew linkage` on Linux**:
   Running `brew linkage --test antigravity` will output warnings about "unwanted system libraries" (GTK3, X11, NSS, DBus, ALSA). This is expected and normal: vendor-compiled Electron binaries dynamically link against host system GUI libraries provided by Fedora, rather than Homebrew-compiled copies.

---

## 4. Desktop Integration & The Session Architecture

Making applications installed in `/home/linuxbrew/.linuxbrew/share/applications` visible to Linux desktop launchers (KDE Application Launcher, KRunner, Vicinae, GNOME) was the most nuanced engineering challenge.

### 4.1 The Problem
By default, Fedora's `XDG_DATA_DIRS` contains:
`/home/<user>/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share`

Homebrew's `/home/linuxbrew/.linuxbrew/share` is missing. As a result, Linux desktop launchers cannot discover Homebrew-installed `.desktop` files or icons.

### 4.2 The Investigation & Failed Approaches
* **Approach 1: `~/.config/environment.d/*.conf` alone**:
  Writing to `environment.d` worked for systemd user services, but Fedora's graphical session initialization on KDE Plasma rewrote `XDG_DATA_DIRS` during display manager startup, discarding the value for GUI processes.
* **Approach 2: Live Process/Service Restarts**:
  Attempting to restart `plasmashell` or launcher services mid-session destabilized terminal windows (e.g., Warp) and the active graphical session. **Rule established**: Never restart running graphical shell services in bootstrap scripts.

### 4.3 The Solution: The Plasma Pre-Startup Hook
KDE Plasma documents that scripts located in `~/.config/plasma-workspace/env/*.sh` are sourced *before* the desktop environment and autostarted applications (such as Vicinae or KRunner) launch.

`scripts/bootstrap-desktop` configures:
1. **Generic Fallback**: `~/.config/environment.d/60-linux-formulas-xdg-data.conf`
2. **KDE Plasma Pre-Startup Hook**: `~/.config/plasma-workspace/env/60-linux-formulas-xdg-data.sh`
3. **Current-Session Notification**: Updates systemd and DBus activation environments (`systemctl --user set-environment`, `dbus-update-activation-environment`) and rebuilds sycoca cache (`kbuildsycoca6`).

This generic hook guarantees that any formula installing `.desktop` entries to `share/applications` is indexed natively without requiring one-off symlinks in `~/.local/share/applications`.

---

## 5. Legacy Migration Tooling

To ensure a smooth transition from previous installation methods, `scripts/migrate-antigravity-v1-fedora` was developed:
* **Dry-Run by Default**: Shows what would be removed without making changes.
* **Strict Package Isolation**: Specifically targets the legacy `antigravity` RPM package and `[antigravity-rpm]` repository.
* **Safeguards**: Ignores unrelated Google repositories (e.g., `google-chrome.repo`, COPR repos) and verifies complete removal upon `--apply`.

---

## 6. Update Automation

The update pipeline ensures maintenance overhead remains minimal:
* `scripts/update-formula.py`: Parses the official download page, extracts version and build metadata, downloads the new tarball, recalculates SHA-256, and atomically updates `Formula/antigravity.rb`.
* `.github/workflows/update-antigravity.yml`: Runs daily via GitHub Actions. If a new version is detected, it runs tests, executes `brew audit --strict`, and opens a pull request.
