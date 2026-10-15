class Vicinae < Formula
  desc "Native extensible command palette for Linux desktops"
  homepage "https://vicinae.com"
  version "0.29.1"
  license "GPL-3.0-only"

  on_intel do
    url "https://github.com/vicinaehq/vicinae/releases/download/v0.29.1/Vicinae-x86_64.AppImage"
    sha256 "44906f2290f0934572f1977de8aa529c3b67d104025a489b32f226fe3b0f3dd9"
  end
  on_arm do
    url "https://github.com/vicinaehq/vicinae/releases/download/v0.29.1/Vicinae-aarch64.AppImage"
    sha256 "369feb20fe987d04ffb1a0b354f28773bd1a1a550a31cdcb22d968e39b141ec0"
  end

  depends_on :linux

  def install
    chmod 0755, cached_download
    system cached_download, "--appimage-extract"
    payload = buildpath/"squashfs-root"
    odie "Vicinae AppImage extraction failed" unless (payload/"AppRun").executable?
    libexec.install payload.children

    (bin/"vicinae").write <<~SH
      #!/bin/bash
      unset APPIMAGE
      export APPDIR="#{opt_libexec}"
      exec "#{opt_libexec}/AppRun" "$@"
    SH

    (share/"icons/hicolor").install (libexec/"usr/share/icons/hicolor").children
    desktop = libexec/"usr/share/applications/vicinae.desktop"
    inreplace desktop, "Exec=vicinae", "Exec=#{opt_bin}/vicinae"
    (share/"applications").install desktop
  end

  def caveats
    <<~EOS
      The upstream AppImage is extracted, so FUSE is not required.
      Run `vicinae server` in your graphical session, then bind `vicinae toggle`
      to a desktop keyboard shortcut. Upgrade with `brew upgrade vicinae`.

      For KDE and other desktop launchers, run:
        #{tap.path}/scripts/bootstrap-desktop
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/vicinae version")
    assert_predicate libexec/"AppRun", :executable?
    assert_path_exists share/"icons/hicolor/512x512/apps/vicinae.png"
    desktop = (share/"applications/vicinae.desktop").read
    assert_match "Exec=#{opt_bin}/vicinae server --replace", desktop
    assert_match "Exec=#{opt_bin}/vicinae toggle", desktop
  end
end
