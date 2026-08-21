class Antigravity < Formula
  desc "Standalone command center for Google Antigravity agents"
  homepage "https://antigravity.google/product/antigravity-2"
  url "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.9.1-4871453687021568/linux-x64/Antigravity.tar.gz"
  sha256 "016dbf6a42c5a49aac4fa403d7a89204a3c7c933799c95ecb91ac2c16fa34ded"
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
