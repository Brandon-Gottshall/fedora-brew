cask "jump-desktop-connect" do
  version "7.1.52"
  sha256 "63546be7660a5542e041ff17f20e650915babab2e36b2c29fad16117998fbb84"

  url "https://mirror.jumpdesktop.com/downloads/connect/JumpDesktopConnect-#{version}.dmg"
  name "Jump Desktop Connect"
  desc "Remote desktop access host application"
  homepage "https://jumpdesktop.com/connect/"

  livecheck do
    url "https://mirror.jumpdesktop.com/downloads/connect/connect-mac.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on :macos

  pkg ".jdc.sparkle_guided.pkg"

  uninstall launchctl: [
              "application.com.p5sys.jump.connect.*",
              "com.p5sys.jump.connect.service",
            ],
            quit:      "com.p5sys.jump.connect.automount",
            pkgutil:   "com.p5sys.jump.connect.*",
            delete:    "/Library/Application Support/Jump Desktop/Connect"

  zap trash: [
    "~/Library/Application Support/Jump Desktop/Connect",
    "~/Library/Caches/com.p5sys.jump.connect",
    "~/Library/Caches/com.p5sys.jump.connect.viewer",
    "~/Library/HTTPStorages/com.p5sys.jump.connect",
    "~/Library/Preferences/com.p5sys.jump.connect.plist",
    "~/Library/Preferences/com.p5sys.jump.connect.viewer.plist",
  ]
end
