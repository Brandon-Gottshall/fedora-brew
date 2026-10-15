cask "jump-desktop-mac" do
  version "9.1.9,90109"
  sha256 "9ed0cf53d0e2a61ca741c2ba999f91e0ca13473b4ca59692a59c67d05c8cc199"

  url "https://mirror.jumpdesktop.com/downloads/jdm/JumpDesktopMac-#{version.csv.second}.zip",
      user_agent: :fake
  name "Jump Desktop"
  desc "Remote desktop client application (RDP, VNC, Fluid)"
  homepage "https://jumpdesktop.com/#jdmac"

  livecheck do
    url "https://mirror.jumpdesktop.com/downloads/jdm/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on :macos

  app "Jump Desktop.app"

  zap trash: [
    "~/Documents/JumpDesktop",
    "~/Library/Caches/com.p5xsoft.jumpdesktop.mac",
    "~/Library/Cookies/com.p5xsoft.jumpdesktop.mac.binarycookies",
    "~/Library/Preferences/com.p5xsoft.jumpdesktop.mac.plist",
  ]
end
