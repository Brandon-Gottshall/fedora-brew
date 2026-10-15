class Flare < Formula
  desc "Unofficial Signal client built with GTK4 and Libadwaita"
  homepage "https://mobile.schmidhuberj.de/flare"
  url "https://gitlab.com/api/v4/projects/37464215/packages/generic/flare/0.22.4/flare-0.22.4.tar.xz"
  sha256 "f4425d20da19c657898e7529f6d500109cb4db97167cee89f51551399edb1bac"
  license "AGPL-3.0-only"

  depends_on "blueprint-compiler" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => :build
  depends_on "protobuf" => :build
  depends_on "rust" => :build
  depends_on "gettext"
  depends_on "glib"
  depends_on "gtk4"
  depends_on "gtksourceview5"
  depends_on "libadwaita"
  depends_on :linux

  def install
    # Use the release's vendored crates, including its pinned Signal backend.
    # The source repository archive does not contain these dependencies.
    ENV["CARGO_NET_OFFLINE"] = "true"
    ENV["SQLX_OFFLINE"] = "true"
    inreplace ".cargo/config", 'directory = "vendor"', "directory = \"#{buildpath}/vendor\""
    system "meson", "setup", "build", *std_meson_args, "-Dprofile=default"
    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  post_install_steps do
    compile_gsettings_schemas
    update_gtk_icon_cache
  end

  def caveats
    <<~EOS
      Flare is an unofficial Signal client. This formula builds the upstream
      vendored source release; the first installation can take considerable time.
      A graphical session and a Secret Service provider (such as GNOME Keyring
      or a compatible KWallet setup) are required for normal desktop use.

      Register the launcher with KDE and other desktops by running:
        #{tap.path}/scripts/bootstrap-desktop
    EOS
  end

  test do
    assert_predicate bin/"flare", :executable?
    assert_path_exists share/"applications/de.schmidhuberj.Flare.desktop"
    assert_path_exists share/"glib-2.0/schemas/gschemas.compiled"
    assert_match bin/"flare", (share/"dbus-1/services/de.schmidhuberj.Flare.service").read
    assert_match "de.schmidhuberj.Flare", shell_output(
      "#{formula_opt_bin("glib")}/gsettings --schemadir=#{share}/glib-2.0/schemas list-schemas",
    )
  end
end
