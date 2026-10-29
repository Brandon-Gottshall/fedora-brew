# Formula Patterns & Archetypes

This guide provides copy-pasteable, battle-tested formula templates for adapting different Linux application packaging formats into Homebrew.

---

## Pattern A: Vendor Tarball / Electron Application

**Use for**: Standalone vendor tarballs (`.tar.gz`, `.tar.xz`), bundled Electron applications (e.g. Antigravity, Slack, Discord, VS Code forks).

```ruby
class ElectronApp < Formula
  desc "Vendor Electron Application"
  homepage "https://example.com"
  url "https://example.com/downloads/v1.2.0/app-linux-x64.tar.gz"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  license :cannot_represent

  livecheck do
    url "https://example.com/downloads"
    regex(/app[._-]v?(\d+(?:\.\d+)+)[._-]linux-x64\.tar\.gz/i)
  end

  depends_on arch: :x86_64
  depends_on :linux

  resource "icon" do
    url "https://example.com/assets/app-icon.png"
    sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
  end

  def install
    # Handle optional archive root directory wrapper
    wrapped_payload = buildpath/"app-linux-x64"
    payload = wrapped_payload.directory? ? wrapped_payload : buildpath

    odie "Expected executable is missing" unless (payload/"app-binary").executable?

    # Install payload into libexec
    libexec.install payload.children

    # Create wrapper in bin/ and disable upstream auto-updater
    (bin/"app-binary").write_env_script libexec/"app-binary", DISABLE_AUTO_UPDATE: "1"

    # Install icon
    resource("icon").stage do
      (share/"icons/hicolor/256x256/apps").install "app-icon.png" => "app-binary.png"
    end

    # Install Desktop Entry using stable opt_bin
    (share/"applications/app-binary.desktop").write <<~DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Electron App
      GenericName=Productivity Tool
      Comment=Example Electron Application
      TryExec=#{opt_bin}/app-binary
      Exec=#{opt_bin}/app-binary %U
      Icon=app-binary
      Terminal=false
      StartupNotify=true
      StartupWMClass=ElectronApp
      Categories=Utility;
    DESKTOP
  end

  def caveats
    <<~EOS
      Desktop discovery uses Homebrew's share directory. Ensure tap bootstrap is configured:
        #{tap.path}/scripts/bootstrap-desktop
    EOS
  end

  test do
    assert_predicate libexec/"app-binary", :executable?
    assert_path_exists share/"icons/hicolor/256x256/apps/app-binary.png"
    assert_match "Exec=#{opt_bin}/app-binary %U", (share/"applications/app-binary.desktop").read
  end
end
```

---

## Pattern B: AppImage Application

**Use for**: Upstream tools distributed exclusively as `.AppImage` binaries.

```ruby
class AppImageTool < Formula
  desc "Application distributed as AppImage"
  homepage "https://example.com"
  url "https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.AppImage"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  license "GPL-3.0-or-later"

  depends_on :linux

  def install
    # AppImages can be extracted using --appimage-extract
    system "./App-#{version}.AppImage", "--appimage-extract"
    payload = buildpath/"squashfs-root"

    odie "AppImage extraction failed" unless payload.directory?

    libexec.install payload.children

    # Create wrapper pointing to extracted entrypoint (or AppRun)
    (bin/"app-tool").write_env_script libexec/"AppRun", APPIMAGE_SILENT_INSTALL: "1"

    # Install desktop entry and icon if bundled in the AppImage
    if (libexec/"app.desktop").exist?
      (share/"applications").install libexec/"app.desktop" => "app-tool.desktop"
      # Rewrite Exec line to stable opt_bin
      inreplace share/"applications/app-tool.desktop", /^Exec=.*$/, "Exec=#{opt_bin}/app-tool %U"
    end

    if (libexec/"app.png").exist?
      (share/"icons/hicolor/256x256/apps").install libexec/"app.png" => "app-tool.png"
    end
  end

  test do
    assert_predicate libexec/"AppRun", :executable?
    assert_predicate bin/"app-tool", :executable?
  end
end
```

---

## Pattern C: Debian (`.deb`) Archive Payload Extraction

**Use for**: Upstream applications that only provide `.deb` packages for Linux (e.g. tools built for Ubuntu/Debian).

```ruby
class DebExtractedApp < Formula
  desc "Application extracted from Debian package"
  homepage "https://example.com"
  url "https://example.com/downloads/v1.0.0/package_1.0.0_amd64.deb"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  license "MIT"

  depends_on arch: :x86_64
  depends_on :linux

  def install
    # Extract data.tar payload from deb archive using ar / tar
    system "ar", "x", "package_#{version}_amd64.deb"

    data_archive = Dir["data.tar.*"].first || "data.tar"
    system "tar", "-xf", data_archive, "-C", buildpath

    # Payloads are usually structured under usr/bin, usr/lib, usr/share
    if (buildpath/"usr/lib/myapp").directory?
      libexec.install (buildpath/"usr/lib/myapp").children
      bin.install_symlink libexec/"myapp"
    elsif (buildpath/"opt/myapp").directory?
      libexec.install (buildpath/"opt/myapp").children
      bin.install_symlink libexec/"myapp"
    end

    # Install bundled desktop files & icons
    if (buildpath/"usr/share/applications").directory?
      (share/"applications").install Dir[buildpath/"usr/share/applications/*.desktop"]
    end
    if (buildpath/"usr/share/icons").directory?
      (share/"icons").install Dir[buildpath/"usr/share/icons/*"]
    end
  end

  test do
    assert_predicate bin/"myapp", :exist?
  end
end
```

---

## Pattern D: Standalone Prebuilt Binary

**Use for**: Single binary CLI tools or utilities published on GitHub Releases.

```ruby
class StandaloneCli < Formula
  desc "Fast standalone CLI tool"
  homepage "https://github.com/example/tool"
  url "https://github.com/example/tool/releases/download/v2.1.0/tool-linux-x86_64.tar.gz"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  license "Apache-2.0"

  on_linux do
    on_intel do
      url "https://github.com/example/tool/releases/download/v2.1.0/tool-linux-x86_64.tar.gz"
      sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    end
    on_arm do
      url "https://github.com/example/tool/releases/download/v2.1.0/tool-linux-aarch64.tar.gz"
      sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
    end
  end

  def install
    bin.install "tool"

    # Optional bash/zsh completions
    generate_completions_from_executable(bin/"tool", "completions") if build.with? "completions"
  end

  test do
    assert_match "tool version 2.1.0", shell_output("#{bin}/tool --version")
  end
end
```
