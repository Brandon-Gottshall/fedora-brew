class ClaudeDesktop < Formula
  desc "Desktop application for Claude.ai"
  homepage "https://claude.com/download"
  url "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_2.7032.0_amd64.deb"
  version "2.7032.0"
  sha256 "1e7f4504bca5b2f6b2d3c4123d145d727647e77f2ee2d046850711e61e7d7b11"
  license :cannot_represent
  revision 2

  livecheck do
    skip "release metadata is read from Anthropic's APT index by update-claude-desktop.py"
  end

  # Like the upstream Debian package, the app uses the desktop's own GTK, NSS,
  # ALSA and Mesa libraries (and so the distro's GPU drivers) rather than
  # Homebrew copies. `scripts/doctor` reports any that a minimal system lacks.
  depends_on arch: :x86_64
  depends_on :linux

  def install
    system "ar", "x", cached_download
    data_archive = Dir["data.tar.*"].first
    odie "Claude Desktop Debian payload is missing" if data_archive.nil?

    system "tar", "-xf", data_archive
    payload = buildpath/"usr/lib/claude-desktop"
    odie "Claude Desktop executable is missing" unless (payload/"claude-desktop").executable?
    odie "Claude Desktop application bundle is missing" unless (payload/"resources/app.asar").exist?

    libexec.install payload.children
    (bin/"claude-desktop").write <<~SH
      #!/bin/bash
      exec "#{opt_libexec}/claude-desktop" "$@"
    SH

    icon_root = buildpath/"usr/share/icons/hicolor"
    odie "Claude Desktop icons are missing" unless icon_root.directory?
    (share/"icons/hicolor").install icon_root.children

    desktop_source = buildpath/"usr/share/applications/com.anthropic.Claude.desktop"
    odie "Claude Desktop launcher is missing" unless desktop_source.exist?
    inreplace desktop_source, "Exec=claude-desktop", "Exec=#{opt_bin}/claude-desktop"
    (share/"applications").install desktop_source
  end

  def caveats
    <<~EOS
      This formula repackages Anthropic's official Ubuntu/Debian Linux beta.
      Fedora and Arch/CachyOS are community packaging targets, not upstream-supported distributions.

      The Debian maintainer scripts are intentionally not run, so APT is not registered
      and Homebrew remains the sole update owner. Upgrade with:
        brew upgrade claude-desktop

      Claude Desktop uses the system's GTK 3, NSS, ALSA and Mesa libraries, which
      every desktop install provides. On a minimal system, run the tap doctor to
      list any that are missing:
        #{tap.path}/scripts/doctor

      Desktop discovery uses Homebrew's share directory. Run the tap bootstrap once:
        #{tap.path}/scripts/bootstrap-desktop
    EOS
  end

  test do
    assert_predicate libexec/"claude-desktop", :executable?
    refute_match "not found", shell_output("ldd #{libexec}/claude-desktop")
    assert_path_exists libexec/"resources/app.asar"
    assert_path_exists share/"icons/hicolor/256x256/apps/claude-desktop.png"

    wrapper = (bin/"claude-desktop").read
    assert_match "exec \"#{opt_libexec}/claude-desktop\"", wrapper

    desktop = (share/"applications/com.anthropic.Claude.desktop").read
    assert_match "Exec=#{opt_bin}/claude-desktop %U", desktop
    assert_match "Exec=#{opt_bin}/claude-desktop \"claude://claude.ai/new", desktop
    refute_match %r{/usr/lib/claude-desktop}, wrapper
  end
end
