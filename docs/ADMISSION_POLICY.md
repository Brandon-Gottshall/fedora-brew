# Package Admission & Ownership Policy

This document defines the admission criteria, package manager boundaries, and ownership rules for the `fedora-brew` tap.

---

## 1. The Core Ownership Invariant

In modern Linux environments, multiple package managers frequently coexist (DNF, Flatpak, Homebrew). To prevent system corruption, conflicting updates, and ghost files, this repository adheres to a strict ownership invariant:

* **DNF / RPM Packages**: Owned, updated, and removed exclusively by DNF.
* **Flatpak Applications**: Owned, updated, and removed exclusively by Flatpak.
* **Fedora Brew Formulae**: Owned, updated, and removed exclusively by Homebrew.

> [!CAUTION]
> **No Delegated Package Installation:**
> A formula in this tap **MUST NEVER** invoke `sudo dnf install`, `flatpak install`, `npm install -g`, `pip install`, or any other external package manager. Doing so breaks Homebrew's ability to track, verify, and cleanly uninstall files.

---

## 2. When to Add a Package to this Tap

An application belongs in this tap if it meets **all** of the following criteria:

1. **Suboptimal Native Packaging**: Upstream lacks an official, well-maintained Fedora DNF repository or an official Flatpak on Flathub, OR upstream distributes Linux applications primarily as:
   * Self-contained vendor tarballs (e.g. `.tar.gz`, `.tar.xz`)
   * AppImages (`.AppImage`)
   * Extracted Debian payloads (`.deb`)
   * Prebuilt standalone Linux binaries
2. **Self-Contained Payload**: The application can reside entirely within its Homebrew Cellar directory (`libexec` or `bin`), without requiring modifications to root filesystem directories (`/usr`, `/etc`, `/var`).
3. **Official HTTPS Source**: Releases are published to trusted, permanent, HTTPS endpoints with reproducible artifact URLs (e.g. GitHub Releases, Google Storage, vendor CDN).
4. **Pin-able Integrity**: The download can be verified using SHA-256 checksums.
5. **No Elevating Privileges**: The software must run in user space without requiring `setuid`, custom kernel modules, or `sudo` during installation.

---

## 3. When NOT to Add a Package

Do **NOT** package software in this tap if:

| Scenario | Preferred Solution |
| :--- | :--- |
| Package is well-maintained in Fedora official repos | Use `sudo dnf install <package>` |
| Application is officially packaged on Flathub | Use `flatpak install flathub <app-id>` |
| Standard CLI tool in official Homebrew core | Use upstream `brew install <tool>` |
| Software requires kernel modules or root daemons | Use system packaging (RPM / systemd) |
| Binary requires arbitrary unpackaged system libraries | Use Flatpak (bundled runtime) or DNF |
| Software modifies root directories on launch | Reject |

---

## 4. User Data & Uninstall Policy

When a package is uninstalled (`brew uninstall <name>`):
* Homebrew removes all files it created in the Cellar, `bin` wrappers, `share/applications/*.desktop`, and `share/icons/*`.
* **User data is preserved**: The formula must not touch `~/.config/<app>`, `~/.local/share/<app>`, credentials, database directories, or project files during uninstall.
