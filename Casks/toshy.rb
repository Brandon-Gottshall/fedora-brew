cask "toshy" do
  version "26.08.0"
  sha256 "81de60a852b3a5abc4b610d55ccc0fe3fbad71df2156cea9d5ab01e6e793ea62"

  url "https://github.com/RedBearAK/toshy/archive/refs/tags/Toshy_v#{version}.tar.gz"
  name "Toshy"
  desc "Desktop-aware keyboard remapping and shortcut customization"
  homepage "https://github.com/RedBearAK/toshy"

  livecheck do
    url :url
    regex(/^Toshy[._-]v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on arch: :x86_64
  depends_on formula: "toshy-runtime"
  depends_on :linux

  artifact "Toshy-Toshy_v#{version}/README.md",
           target: "#{HOMEBREW_PREFIX}/share/doc/toshy/README.md"

  postflight do
    system_command "#{HOMEBREW_PREFIX}/bin/toshy-brew-sync",
                   args: [
                     "install",
                     "--source", "#{staged_path}/Toshy-Toshy_v#{version}",
                     "--runtime", "#{HOMEBREW_PREFIX}/opt/toshy-runtime/libexec/runtime"
                   ]
  end

  uninstall script: {
    executable: "#{HOMEBREW_PREFIX}/bin/toshy-brew-sync",
    args:       ["uninstall"],
    sudo:       false,
  }

  zap trash: [
    "~/.config/toshy",
    "~/.local/state/linux-formulas/backups/toshy",
    "~/.local/state/linux-formulas/integrations/toshy.json",
    "~/.local/state/toshy/runtime",
  ]
end
