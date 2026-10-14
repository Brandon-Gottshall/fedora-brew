class ToshyRuntime < Formula
  include Language::Python::Virtualenv

  desc "Externally managed Python runtime for Toshy"
  homepage "https://github.com/RedBearAK/toshy"
  url "https://github.com/RedBearAK/toshy/archive/refs/tags/Toshy_v26.08.0.tar.gz"
  version "26.08.0"
  sha256 "81de60a852b3a5abc4b610d55ccc0fe3fbad71df2156cea9d5ab01e6e793ea62"
  license "GPL-3.0-or-later"

  livecheck do
    url :stable
    regex(/^Toshy[._-]v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "patchelf" => :build
  depends_on "pkgconf" => :build
  depends_on arch: :x86_64
  depends_on "dbus"
  depends_on "gtk+3"
  depends_on "gtk4"
  depends_on "libadwaita"
  depends_on "libayatana-appindicator"
  depends_on "libffi"
  depends_on "libxkbcommon"
  depends_on :linux
  depends_on "pillow"
  depends_on "py3cairo"
  depends_on "pygobject3"
  depends_on "python-tk@3.14"
  depends_on "python@3.14"
  depends_on "systemd"
  depends_on "wayland"

  resource "setuptools" do
    url "https://files.pythonhosted.org/packages/94/b8/f1f62a5e3c0ad2ff1d189590bfa4c46b4f3b6e49cef6f26c6ee4e575394d/setuptools-80.10.2-py3-none-any.whl"
    sha256 "95b30ddfb717250edb492926c92b5221f7ef3fbcc2b07579bcd4a27da21d0173"
  end

  resource "wheel" do
    url "https://files.pythonhosted.org/packages/87/22/b76d483683216dde3d67cba61fb2444be8d5be289bf628c13fc0fd90e5f9/wheel-0.46.3-py3-none-any.whl"
    sha256 "4b399d56c9d9338230118d705d9737a2a468ccca63d5e813e2a4fc7815d8bc4d"
  end

  resource "packaging" do
    url "https://files.pythonhosted.org/packages/b7/b9/c538f279a4e237a006a2c98387d081e9eb060d203d8ed34467cc0f0b9b53/packaging-26.0-py3-none-any.whl"
    sha256 "b36f1fef9334a5588b4166f8bcd26a14e521f2b55e6b9de3aaa80d3ff7a37529"
  end

  resource "pathspec" do
    url "https://files.pythonhosted.org/packages/ef/3c/2c197d226f9ea224a9ab8d197933f9da0ae0aac5b6e0f884e2b8d9c8e9f7/pathspec-1.0.4-py3-none-any.whl"
    sha256 "fb6ae2fd4e7c921a165808a552060e722767cfa526f99ca5156ed2ce45a5c723"
  end

  resource "pluggy" do
    url "https://files.pythonhosted.org/packages/54/20/4d324d65cc6d9205fabedc306948156824eb9f0ee1633355a8f7ec5c66bf/pluggy-1.6.0-py3-none-any.whl"
    sha256 "e920276dd6813095e9377c0bc5566d94c932c33b27a3e3945d8389c374dd4746"
  end

  resource "trove-classifiers" do
    url "https://files.pythonhosted.org/packages/bb/4a/2e5583e544bc437d5e8e54b47db87430df9031b29b48d17f26d129fa60c0/trove_classifiers-2026.1.14.14-py3-none-any.whl"
    sha256 "1f9553927f18d0513d8e5ff80ab8980b8202ce37ecae0e3274ed2ef11880e74d"
  end

  resource "hatchling" do
    url "https://files.pythonhosted.org/packages/d3/8a/44032265776062a89171285ede55a0bdaadc8ac00f27f0512a71a9e3e1c8/hatchling-1.29.0-py3-none-any.whl"
    sha256 "50af9343281f34785fab12da82e445ed987a6efb34fd8c2fc0f6e6630dbcc1b0"
  end

  resource "meson-python" do
    url "https://files.pythonhosted.org/packages/16/7f/d1b0c65b267a1463d752b324f11d3470e30889daefc4b9ec83029bfa30b5/meson_python-0.19.0-py3-none-any.whl"
    sha256 "67b5906c37404396d23c195e12c8825506074460d4a2e7083266b845d14f0298"
  end

  resource "pyproject-metadata" do
    url "https://files.pythonhosted.org/packages/1d/0b/da4851b1e2d9c40c9bd74c0abd94510a7d797da9ccde0a90e8953751ed4a/pyproject_metadata-0.11.0-py3-none-any.whl"
    sha256 "85bbecca8694e2c00f63b492c96921d6c228454057c88e7c352b2077fcaa4096"
  end

  resource "anyascii" do
    url "https://files.pythonhosted.org/packages/c2/76/783b75a21ce3563b8709050de030ae253853b147bd52e141edc1025aa268/anyascii-0.3.3-py3-none-any.whl"
    sha256 "f5ab5e53c8781a36b5a40e1296a0eeda2f48c649ef10c3921c1381b1d00dee7a"
  end

  resource "appdirs" do
    url "https://files.pythonhosted.org/packages/3b/00/2344469e2084fb287c2e0b57b72910309874c3245463acd6cf5e3db69324/appdirs-1.4.4-py2.py3-none-any.whl"
    sha256 "a841dacd6b99318a741b166adb07e19ee71a274450e68237b4650ca1055ab128"
  end

  resource "dbus-python" do
    url "https://files.pythonhosted.org/packages/c1/d3/6be85a9c772d6ebba0cc3ab37390dd6620006dcced758667e0217fb13307/dbus-python-1.3.2.tar.gz"
    sha256 "ad67819308618b5069537be237f8e68ca1c7fcc95ee4a121fe6845b1418248f8"
  end

  resource "evdev" do
    url "https://files.pythonhosted.org/packages/a5/f5/397b61091120a9ca5001041dd7bf76c385b3bfd67a0e5bcb74b852bd22a4/evdev-1.9.3.tar.gz"
    sha256 "2c140e01ac8437758fa23fe5c871397412461f42d421aa20241dc8fe8cfccbc9"
  end

  resource "hyprpy" do
    url "https://files.pythonhosted.org/packages/05/34/5b522969230b27fd5da3a4f48c16e1b9d5fe1dd2cd3b4837887c5a8b3067/hyprpy-0.1.10-py3-none-any.whl"
    sha256 "a2373546c25bf4ebab37ca68909c3191721b62afc598e76181c4d2218a81fbaa"
  end

  resource "i3ipc" do
    url "https://files.pythonhosted.org/packages/de/30/294b07ddeccb58855c890c3ef3a951c3b0c1e2d089666d548b6a9edc39fb/i3ipc-2.2.1-py3-none-any.whl"
    sha256 "c0b898223d50d42c90c818deb5033d1304c582755547dee7d15df3e3781bc690"
  end

  resource "inotify-simple" do
    url "https://files.pythonhosted.org/packages/51/41/59ca6011f5463d5e5eefcfed2e7fe470922d3a958b7f3aad95eda208d7d3/inotify_simple-1.3.5.tar.gz"
    sha256 "8440ffe49c4ae81a8df57c1ae1eb4b6bfa7acb830099bfb3e305b383005cc128"
  end

  resource "ordered-set" do
    url "https://files.pythonhosted.org/packages/33/55/af02708f230eb77084a299d7b08175cff006dea4f2721074b92cdb0296c0/ordered_set-4.1.0-py3-none-any.whl"
    sha256 "046e1132c71fcf3330438a539928932caf51ddbc582496833e23de611de14562"
  end

  resource "six" do
    url "https://files.pythonhosted.org/packages/b7/ce/149a00dd41f10bc29e5921b496af8b574d8413afcd5e30dfa0ed46c2cc5e/six-1.17.0-py2.py3-none-any.whl"
    sha256 "4721f391ed90541fddacab5acf947aa0d3dc7d27b2e1e8eda2be8970586c3274"
  end

  resource "python-xlib" do
    url "https://files.pythonhosted.org/packages/c2/16/950463d36e8b64067c4d535038c5512de8200015e793d7d0a3f400187cbf/python_xlib-0.31-py2.py3-none-any.whl"
    sha256 "1ec6ce0de73d9e6592ead666779a5732b384e5b8fb1f1886bd0a81cafa477759"
  end

  resource "cffi" do
    url "https://files.pythonhosted.org/packages/47/d9/d83e293854571c877a92da46fdec39158f8d7e68da75bf73581225d28e90/cffi-2.0.0-cp314-cp314-manylinux2014_x86_64.manylinux_2_17_x86_64.whl"
    sha256 "afb8db5439b81cf9c9d0c80404b60c3cc9c3add93e114dcae767f1477cb53775"
  end

  resource "pycparser" do
    url "https://files.pythonhosted.org/packages/0c/c3/44f3fbbfa403ea2a7c779186dc20772604442dde72947e7d01069cbe98e3/pycparser-3.0-py3-none-any.whl"
    sha256 "b727414169a36b7d524c1c3e31839a521725078d7b2ff038656844266160a992"
  end

  resource "pywayland" do
    url "https://files.pythonhosted.org/packages/20/93/bc9b258dcb46aafc587438355a9170c3be05a6abb5cd55bf1d600d848fa0/pywayland-0.4.18.tar.gz"
    sha256 "598ade02783aad05a328f663b51b694c5ab68bd5d1e0926c0da3c5212c566533"
  end

  resource "lockfile" do
    url "https://files.pythonhosted.org/packages/c8/22/9460e311f340cb62d26a38c419b1381b8593b0bb6b5d1f056938b086d362/lockfile-0.12.2-py2.py3-none-any.whl"
    sha256 "6c3cb24f344923d30b2785d5ad75182c8ea7ac1b6171b08657258ec7429d50fa"
  end

  resource "systemd-python" do
    url "https://files.pythonhosted.org/packages/10/9e/ab4458e00367223bda2dd7ccf0849a72235ee3e29b36dce732685d9b7ad9/systemd-python-235.tar.gz"
    sha256 "4e57f39797fd5d9e2d22b8806a252d7c0106c936039d1e71c8c6b8008e695c0a"
  end

  resource "sv-ttk" do
    url "https://files.pythonhosted.org/packages/5b/36/32629d8bab9bccd54a36716a960ba1148fca4c1fd453370dba0b42d712ea/sv_ttk-2.6.1-py3-none-any.whl"
    sha256 "8ca5944f95431a911986b00c54e7f44608f3f811382cd985fd14bb3e65f95d97"
  end

  resource "watchdog" do
    url "https://files.pythonhosted.org/packages/db/7d/7f3d619e951c88ed75c6037b246ddcf2d322812ee8ea189be89511721d54/watchdog-6.0.0.tar.gz"
    sha256 "9ddf7c82fda3ae8e24decda1338ede66e1c99883db93711d8fb941eaa2d8c282"
  end

  resource "psutil" do
    url "https://files.pythonhosted.org/packages/aa/c6/d1ddf4abb55e93cebc4f2ed8b5d6dbad109ecb8d63748dd2b20ab5e57ebe/psutil-7.2.2.tar.gz"
    sha256 "0746f5f8d406af344fd547f1c8daa5f5c33dbc293bb8d6a16d80b4bb88f59372"
  end

  resource "xkbcommon" do
    url "https://files.pythonhosted.org/packages/03/29/fd4be2098b0a963c95d5f9cbd03bcf3f5bf741632a994395f62de6b4ef69/xkbcommon-1.0.1.tar.gz"
    sha256 "9e9749d6ecba514161662a468ba38689ab6b6e962af42e09fba5eeabcb776c91"
  end

  resource "annotated-types" do
    url "https://files.pythonhosted.org/packages/78/b6/6307fbef88d9b5ee7421e68d78a9f162e0da4900bc5f5793f6d3d0e34fb8/annotated_types-0.7.0-py3-none-any.whl"
    sha256 "1f02e8b43a8fbbc3f3e0d4f0f4bfc8131bcb4eebe8849b8e5c773f3a1c582a53"
  end

  resource "typing-extensions" do
    url "https://files.pythonhosted.org/packages/18/67/36e9267722cc04a6b9f15c7f3441c2363321a3ea07da7ae0c0707beb2a9c/typing_extensions-4.15.0-py3-none-any.whl"
    sha256 "f0fa19c6845758ab08074a0cfa8b7aecb71c999ca73d62883bc25cc018c4e548"
  end

  resource "typing-inspection" do
    url "https://files.pythonhosted.org/packages/dc/9b/47798a6c91d8bdb567fe2698fe81e0c6b7cb7ef4d13da4114b41d239f65d/typing_inspection-0.4.2-py3-none-any.whl"
    sha256 "4ed1cacbdc298c220f1bd249ed5287caa16f34d44ef4e9c3d0cbad5b521545e7"
  end

  resource "pydantic-core" do
    url "https://files.pythonhosted.org/packages/4c/d2/ef2074dc020dd6e109611a8be4449b98cd25e1b9b8a303c2f0fca2f2bcf7/pydantic_core-2.41.5-cp314-cp314-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
    sha256 "22f0fb8c1c583a3b6f24df2470833b40207e907b90c928cc8d3594b76f874375"
  end

  resource "pydantic" do
    url "https://files.pythonhosted.org/packages/5a/87/b70ad306ebb6f9b585f114d0ac2137d792b48be34d732d60e597c2f8465a/pydantic-2.12.5-py3-none-any.whl"
    sha256 "e561593fccf61e8a20fc46dfc2dfe075b8be7d0188df33f221ad1f0139180f9d"
  end

  def install
    source = libexec/"source"
    source.install buildpath.children

    runtime = libexec/"runtime"
    venv = virtualenv_create(runtime, "python3.14", system_site_packages: true)
    ENV["PIP_NO_INDEX"] = "1"
    ENV.prepend_path "PATH", runtime/"bin"

    build_resources = %w[
      setuptools wheel packaging pathspec pluggy trove-classifiers hatchling
      pyproject-metadata meson-python
    ]
    runtime_resources = %w[
      anyascii appdirs dbus-python evdev annotated-types typing-extensions
      typing-inspection pydantic-core pydantic hyprpy i3ipc inotify-simple
      ordered-set six python-xlib pycparser cffi pywayland lockfile systemd-python
      sv-ttk watchdog psutil xkbcommon
    ]
    (build_resources + runtime_resources).each do |name|
      item = resource(name)
      item.stage do
        target = item.url.end_with?(".whl") ? Pathname.pwd/item.downloader.basename : Pathname.pwd
        venv.pip_install target, build_isolation: false
      end
    end
    venv.pip_install source/"vendors/xwaykeyz-main", build_isolation: false

    python = runtime/"bin/python"
    python.rename runtime/"bin/python-real"
    gi_paths = %w[
      atk gdk-pixbuf graphene gtk+3 gtk4 harfbuzz libadwaita
      libayatana-appindicator libdbusmenu pango pygobject3
    ].filter_map do |name|
      formula = Formula[name]
      path = formula.opt_lib/"girepository-1.0"
      path if path.exist?
    end
    (runtime/"bin/python").write <<~SH
      #!/bin/bash
      export GI_TYPELIB_PATH="#{gi_paths.join(":")}${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      export XDG_DATA_DIRS="#{HOMEBREW_PREFIX}/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
      export PATH="#{HOMEBREW_PREFIX}/bin:$PATH"
      exec "#{runtime}/bin/python-real" "$@"
    SH

    integration = tap.path/"scripts/toshy-brew-sync.py"
    odie "tap integration helper is missing" unless integration.exist?
    bin.install integration => "toshy-brew-sync"
    chmod 0755, bin/"toshy-brew-sync"
    (bin/"toshy-brew-doctor").make_symlink "toshy-brew-sync"
  end

  def caveats
    <<~EOS
      This formula supplies Toshy's runtime. Install the user integration with:
        brew install --cask Brandon-Gottshall/fedora-brew/toshy
    EOS
  end

  test do
    system libexec/"runtime/bin/python", "-c", <<~PYTHON
      import dbus, gi, psutil, watchdog, xkbcommon, systemd, xwaykeyz
      from xwaykeyz.version import __version__
      assert __version__ == "1.25.1"
    PYTHON
    assert_match "usage:", shell_output("#{bin}/toshy-brew-sync --help")
  end
end
