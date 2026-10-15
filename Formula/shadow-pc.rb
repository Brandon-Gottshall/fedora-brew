class ShadowPc < Formula
  desc "Cloud gaming client for Shadow PC"
  homepage "https://shadow.tech/"
  url "https://update.shadow.tech/launcher/prod/linux/ubuntu_18.04/ShadowPC.AppImage"
  version "9.9.10457.17055"
  sha256 "5dc931780f2b58fe12b5b4f8d59adb13b838ced352ddb6cc361edbba102aab11"
  license :cannot_represent

  livecheck do
    skip "version is embedded in the rolling AppImage and checked by update-shadow-pc.py"
  end

  depends_on arch: :x86_64
  depends_on :linux

  def install
    chmod 0755, cached_download
    system cached_download, "--appimage-extract"
    payload = buildpath/"squashfs-root"
    odie "Shadow AppImage extraction failed" unless (payload/"AppRun").executable?
    odie "Shadow desktop metadata is missing" unless (payload/"shadow-launcher.desktop").exist?

    (payload/"resources/app-update.yml").unlink if (payload/"resources/app-update.yml").exist?
    libexec.install payload.children

    (bin/"shadow-pc").write <<~SH
      #!/bin/bash
      unset APPIMAGE
      export APPDIR="#{opt_libexec}"
      exec "#{opt_libexec}/AppRun" --no-sandbox "$@"
    SH

    icon_dir = share/"icons/hicolor/256x256/apps"
    icon_dir.install libexec/"usr/share/icons/hicolor/256x256/apps/shadow-launcher.png"
    (share/"applications/shadow-pc.desktop").write <<~DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Shadow PC
      Comment=Launch the Shadow PC cloud gaming client
      TryExec=#{opt_bin}/shadow-pc
      Exec=#{opt_bin}/shadow-pc %U
      Icon=shadow-launcher
      Terminal=false
      StartupNotify=true
      StartupWMClass=Shadow PC
      MimeType=x-scheme-handler/tech.shadow;
      Categories=Game;
    DESKTOP
  end

  def caveats
    <<~EOS
      Shadow's bundled updater is disabled. Use `brew upgrade shadow-pc`.

      To register desktop applications from this tap, run:
        #{tap.path}/scripts/bootstrap-desktop
    EOS
  end

  test do
    assert_predicate libexec/"AppRun", :executable?
    refute_path_exists libexec/"resources/app-update.yml"
    assert_match "--no-sandbox", (bin/"shadow-pc").read
    assert_match "export APPDIR=\"#{opt_libexec}\"", (bin/"shadow-pc").read
    assert_match "Exec=#{opt_bin}/shadow-pc %U", (share/"applications/shadow-pc.desktop").read
  end
end
