class JumpDesktop < Formula
  desc "Remote desktop client with advanced hotkey passthrough"
  homepage "https://jumpdesktop.com"
  url "https://github.com/electron/electron/releases/download/v34.2.0/electron-v34.2.0-linux-x64.zip"
  version "1.0.0"
  sha256 "f12a02d86cc657500978d263ec6d1841b6e2085cd3bd4d30a97cfe14685396f3"
  license :cannot_represent

  livecheck do
    url "https://github.com/electron/electron/releases"
    regex(%r{/v?(\d+(?:\.\d+)+)/electron-v?\d+(?:\.\d+)+-linux-x64\.zip}i)
  end

  depends_on arch: :x86_64
  depends_on :linux

  def install
    odie "Expected Electron binary is missing" unless (buildpath/"electron").executable?

    # Install Electron framework into libexec
    libexec.install Dir["*"]

    # Stage our custom Jump Desktop web wrapper application
    app_dir = libexec/"resources/app"
    app_dir.mkpath

    if tap && (tap.path/"src/jump-desktop-app").directory?
      cp_r (tap.path/"src/jump-desktop-app").children, app_dir
    end

    # Create binary launcher wrapper
    (bin/"jump-desktop").write_env_script libexec/"electron",
                                          DISABLE_AUTO_UPDATE:        "1",
                                          ELECTRON_FORCE_IS_PACKAGED: "true"

    # Install icon
    if (app_dir/"icon.png").exist?
      (share/"icons/hicolor/256x256/apps").mkpath
      cp app_dir/"icon.png", share/"icons/hicolor/256x256/apps/jump-desktop.png"
    end

    # Install Desktop Entry
    (share/"applications/jump-desktop.desktop").write <<~DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Jump Desktop
      GenericName=Remote Desktop Client
      Comment=High-performance remote desktop client with advanced hotkey passthrough
      TryExec=#{opt_bin}/jump-desktop
      Exec=#{opt_bin}/jump-desktop %U
      Icon=jump-desktop
      Terminal=false
      StartupNotify=true
      StartupWMClass=jump-desktop
      Categories=Network;RemoteAccess;Development;
    DESKTOP
  end

  def caveats
    <<~EOS
      Jump Desktop Hotkey Controls:
        • Ctrl + Shift + M : Toggle between Strict Passthrough and Mac Mode (Cmd swap)
        • Ctrl + Shift + F : Toggle Fullscreen (or F11)
        • Ctrl + Shift + R : Reload session
        • Ctrl + Shift + Q : Quit application
        • Hover over top edge of screen to reveal the floating control pill.

      Three-finger trackpad swipes are forwarded only while the Jump window is
      focused and Remote Locked. They send Cmd+Option+Ctrl+Shift plus the arrow
      matching the swipe direction. Set JUMP_DESKTOP_GESTURE_THRESHOLD to tune
      sensitivity, or JUMP_DESKTOP_TOUCHPAD_DEVICE to a /dev/input/event* path.

      Session cookies & settings are stored in ~/.config/jump-desktop/
    EOS
  end

  test do
    assert_predicate libexec/"electron", :executable?
    assert_path_exists bin/"jump-desktop"
    assert_path_exists libexec/"resources/app/main.js"
    assert_path_exists share/"icons/hicolor/256x256/apps/jump-desktop.png"

    desktop = share/"applications/jump-desktop.desktop"
    assert_match "Exec=#{opt_bin}/jump-desktop %U", desktop.read
  end
end
