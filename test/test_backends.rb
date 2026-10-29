# frozen_string_literal: true
require "stringio"
require "tmpdir"
require "digest"
require "fileutils"
require_relative "../lib/linux_formulas/app"

class BackendsTest
  def assert(value, message = "assertion failed")
    raise message unless value
  end

  def refute(value)
    assert(!value)
  end

  def assert_equal(expected, actual)
    assert(expected == actual, "expected #{expected.inspect}, got #{actual.inspect}")
  end

  def assert_includes(value, expected)
    assert(value.include?(expected), "#{value.inspect} must include #{expected.inspect}")
  end

  def refute_includes(value, expected)
    refute(value.include?(expected))
  end

  def assert_empty(value)
    assert(value.empty?)
  end

  def assert_match(pattern, value)
    assert(pattern.match?(value))
  end

  def assert_raises(type)
    begin
      yield
    rescue type
      return
    end
    raise "Expected #{type}"
  end

  def capture_io
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = StringIO.new, StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout, $stderr = original_out, original_err
  end
  def setup
    @temp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@temp)
  end

  def platform(content, host_os: "linux")
    path = File.join(@temp, "os-release")
    File.write(path, content)
    LinuxFormulas::Platform.new(os_release: path, host_os: host_os)
  end

  def catalog(os)
    LinuxFormulas::Catalog.new(platform: os)
  end

  # A package-manager runner answering from a table of "command line" => stdout.
  def fake_runner(responses = {})
    ->(cmd) { responses.key?(cmd.join(" ")) ? [responses[cmd.join(" ")], true] : ["", false] }
  end

  def fake_host(os, responses = {}, aur_helper: nil, apps_dir: nil)
    LinuxFormulas::System.new(platform: os, aur_helper: aur_helper, apps_dir: apps_dir || File.join(@temp, "apps"),
                              runner: fake_runner(responses))
  end

  def test_distro_detection_uses_id_and_id_like
    assert_equal "arch", platform("ID=cachyos\nID_LIKE=arch\n").family
    assert_equal "arch", platform("ID=custom\nID_LIKE=\"arch linux\"\n").family
    assert_equal "fedora", platform("ID=fedora\n").family
    assert_equal "debian", platform("ID=debian\n").family
    assert_equal "macos", platform("", host_os: "arm64-darwin").family
  end

  def test_platform_filters_backends_and_defaults
    arch = platform("ID=cachyos\nID_LIKE=arch\n")
    jump = catalog(arch).find("jump-desktop")
    assert_equal "brew", jump.default_backend
    assert jump.has_backend?("pacman")
    refute jump.has_backend?("rpm")
    refute jump.backend("brew").key?("cask")
    assert catalog(arch).find("vicinae").has_backend?("aur")
    mac = catalog(platform("", host_os: "darwin")).find("jump-desktop")
    assert_equal ["brew"], mac.backend_names
    assert_match %r{/jump-desktop-mac\z}, mac.backend("brew")["cask"]
    assert_empty catalog(platform("", host_os: "darwin")).find("claude-desktop").backend_names
    fedora = catalog(platform("ID=fedora\n")).find("antigravity")
    assert_equal "rpm", fedora.default_backend
    assert fedora.has_backend?("rpm")
  end

  def test_resolver_rejects_cross_platform_backend_and_normalizes_native
    os = platform("ID=cachyos\n")
    state = LinuxFormulas::State.new(config_dir: @temp, platform: os)
    resolver = LinuxFormulas::Resolver.new(state: state)
    jump = catalog(os).find("jump-desktop")
    assert_equal "pacman", resolver.resolve(jump, explicit_backend: "native", interactive: false)
    assert_raises(RuntimeError) { resolver.resolve(jump, explicit_backend: "rpm", interactive: false) }
    state.set_config("default_backend", "native")
    assert_equal "pacman", resolver.resolve(jump, interactive: false)
  end

  def test_unknown_native_backend_is_not_silently_replaced_by_brew
    os = platform("ID=ubuntu\n")
    state = LinuxFormulas::State.new(config_dir: @temp, platform: os)
    resolver = LinuxFormulas::Resolver.new(state: state)
    package = catalog(os).find("claude-desktop")
    assert_raises(RuntimeError) { resolver.resolve(package, explicit_backend: "native", interactive: false) }
    state.set_config("default_backend", "native")
    assert_equal "brew", resolver.resolve(package, interactive: false)
  end

  def test_pacman_avoids_partial_upgrade_and_preserves_confirmation
    backend = LinuxFormulas::Backends::Pacman.new(dry_run: true)
    pkg = LinuxFormulas::Package.new({"name" => "example"})
    out, = capture_io { assert backend.install({}, pkg) }
    assert_includes out, "sudo pacman -Syu --needed example"
    refute_includes out, "--noconfirm"
    out, = capture_io { assert backend.upgrade({}, pkg, interactive: false) }
    assert_includes out, "-Syu --needed --noconfirm example"
  end

  def test_aur_helper_is_an_executable_and_never_run_as_root
    helper = File.join(@temp, "custom-helper")
    File.write(helper, "#!/bin/sh\nexit 0\n")
    File.chmod(0755, helper)
    backend = LinuxFormulas::Backends::Aur.new(dry_run: true, helper: helper)
    pkg = LinuxFormulas::Package.new({"name" => "example"})
    assert backend.available?
    out, = capture_io { assert backend.install({}, pkg) }
    assert_includes out, "#{helper} -Syu --needed example"
    refute_includes out, "sudo"
    missing = LinuxFormulas::Backends::Aur.new(dry_run: true, helper: "missing; touch /tmp/unsafe")
    refute missing.available?
    capture_io { refute missing.install({}, pkg) }
  end

  def test_removed_manifest_can_be_uninstalled_with_recorded_backend
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=arch\n"), host: fake_host(platform("ID=arch\n")))
    app.state.record_install("removed-package", "pacman")
    out, = capture_io { app.run(%w[uninstall removed-package]) }
    assert_includes out, "sudo pacman -R removed-package"
  end

  def test_success_records_platform_and_failed_install_does_not
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=cachyos\n"), host: fake_host(platform("ID=cachyos\n")))
    backend = app.backends.fetch("pacman")
    backend.define_singleton_method(:install) { |*| false }
    capture_io { assert_raises(SystemExit) { app.run(%w[install jump-desktop --pacman]) } }
    assert_empty app.state.installed
    backend.define_singleton_method(:install) { |*| true }
    capture_io { app.run(%w[install jump-desktop --pacman]) }
    assert_equal "arch", app.state.get_installed("jump-desktop").dig("metadata", "distro")
  end

  def test_existing_install_is_adopted_instead_of_reinstalled
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=cachyos\n"), host: fake_host(platform("ID=cachyos\n")))
    backend = app.backends.fetch("flatpak")
    backend.define_singleton_method(:installed?) { |*| true }
    backend.define_singleton_method(:install) { |*| raise "must not install over an existing copy" }
    out, = capture_io { app.run(%w[install moonlight --flatpak]) }
    assert_includes out, "already installed via FLATPAK; adopting it"
    assert_equal "com.moonlight_stream.Moonlight",
                 app.state.get_installed("moonlight").dig("metadata", "package_definition", "app_id")
  end

  def test_lifecycle_uses_canonical_catalog_name
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=arch\n"), host: fake_host(platform("ID=arch\n")))
    app.state.record_install("jump-desktop", "pacman")
    backend = app.backends.fetch("pacman")
    calls = []
    backend.define_singleton_method(:upgrade) { |*| calls << :upgrade; true }
    backend.define_singleton_method(:uninstall) { |*| calls << :uninstall; true }
    capture_io { app.run(%w[upgrade Jump-Desktop]) }
    capture_io { app.run(%w[uninstall JUMP-DESKTOP]) }
    assert_equal [:upgrade, :uninstall], calls
    assert_empty app.state.installed
  end

  def test_removed_manifest_uses_saved_backend_package_identity
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=arch\n"), host: fake_host(platform("ID=arch\n")))
    app.state.record_install("removed-package", "aur", metadata: {"package_definition" => {"package" => "real-package-bin"}})
    out, = capture_io { app.run(%w[uninstall removed-package]) }
    assert_includes out, "sudo pacman -R real-package-bin"
    refute_includes out, "sudo pacman -R removed-package"
  end

  def test_aur_upgrade_and_remove_do_not_require_same_helper
    helper = File.join(@temp, "helper")
    File.write(helper, "#!/bin/sh\nexit 0\n")
    File.chmod(0755, helper)
    backend = LinuxFormulas::Backends::Aur.new(dry_run: true, helper: helper)
    pkg = LinuxFormulas::Package.new({"name" => "example"})
    out, = capture_io { assert backend.upgrade({"package" => "example-bin"}, pkg, interactive: false) }
    assert_includes out, "#{helper} -Syu --needed --noconfirm example-bin"
    File.unlink(helper)
    out, = capture_io { assert backend.uninstall({"package" => "example-bin"}, pkg) }
    assert_includes out, "sudo pacman -R example-bin"
  end

  def test_dry_runs_do_not_mutate_installed_state
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=cachyos\n"), host: fake_host(platform("ID=cachyos\n")))
    capture_io { app.run(%w[install jump-desktop --pacman --yes]) }
    assert_empty app.state.installed
    refute File.exist?(app.state.state_file)
    app.state.record_install("jump-desktop", "pacman")
    original = File.read(app.state.state_file)
    capture_io { app.run(%w[uninstall jump-desktop]) }
    assert_equal original, File.read(app.state.state_file)
  end

  class FakeGithub < LinuxFormulas::Github
    attr_accessor :release, :searches

    def initialize(release = nil)
      super(token: false, arch: "x86_64")
      @release = release
      @searches = 0
    end

    def find_repository(name)
      @searches += 1
      { "full_name" => "example/#{name}", "stars" => 42 }
    end

    def latest_release(_repository)
      @release
    end
  end

  def release_backend(klass, github: FakeGithub.new, files: {})
    backend = klass.new(github: github, apps_dir: File.join(@temp, "apps"), bin_dir: File.join(@temp, "bin"))
    backend.define_singleton_method(:fetch) { |url, destination| FileUtils.cp(files.fetch(url), destination); true }
    backend
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def test_catalog_aliases_resolve_to_the_canonical_package
    assert_equal "claude-code", catalog(platform("ID=cachyos\n")).find("Claude").name
  end

  def test_distro_sections_can_exclude_shared_backends
    assert_equal ["pacman"], catalog(platform("ID=cachyos\n")).find("claude").backend_names
    assert_equal ["brew"], catalog(platform("ID=fedora\n")).find("claude").backend_names
  end

  def with_stdin(text)
    original = $stdin
    $stdin = StringIO.new(text)
    yield
  ensure
    $stdin = original
  end

  def test_backend_prompt_can_be_cancelled_and_reasks_on_bad_input
    os = platform("ID=cachyos\n")
    resolver = LinuxFormulas::Resolver.new(state: LinuxFormulas::State.new(config_dir: @temp, platform: os))
    jump = catalog(os).find("jump-desktop")
    %W[q\n cancel\n #{""}].each do |input|
      with_stdin(input) do
        capture_io { assert_raises(LinuxFormulas::Resolver::Cancelled) { resolver.send(:prompt_user, jump) } }
      end
    end
    with_stdin("bogus\n\n") do
      out, = capture_io { assert_equal jump.default_backend, resolver.send(:prompt_user, jump) }
      assert_includes out, "Not an option: 'bogus'"
    end
    with_stdin("2\n") do
      capture_io { assert_equal (jump.backend_names - [jump.default_backend]).first, resolver.send(:prompt_user, jump) }
    end
  end

  def test_select_asset_prefers_native_arch_and_linux_archives
    github = FakeGithub.new
    assets = %w[tool-aarch64.AppImage tool-x86_64.AppImage tool-src.tar.gz tool-darwin-x64.tar.gz tool-linux-amd64.tar.gz]
               .map { |name| { "name" => name } }
    assert_equal "tool-x86_64.AppImage", github.select_asset(assets, "appimage")["name"]
    assert_equal "tool-linux-amd64.tar.gz", github.select_asset(assets, "archive")["name"]
    assert_equal nil, github.select_asset([{ "name" => "tool-arm64.AppImage" }], "appimage")
  end

  def test_discovery_searches_github_only_when_nothing_else_matches
    github = FakeGithub.new({ "tag" => "v1", "assets" => [{ "name" => "x-x86_64.AppImage", "url" => "u" }] })
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=cachyos\n"), github: github, host: fake_host(platform("ID=cachyos\n")))
    discovery = app.discovery
    %w[flatpak pacman aur].each { |b| app.backends.fetch(b).define_singleton_method(:available?) { true } }
    discovery.define_singleton_method(:probe_flatpak) do |name|
      [LinuxFormulas::Discovery::Candidate.new(backend: "flatpak", package_def: { "app_id" => "org.x.#{name}" }, label: name, detail: "")]
    end
    discovery.define_singleton_method(:probe_pacman) { |_| [] }
    discovery.define_singleton_method(:probe_aur) { |_| [] }
    assert_equal ["flatpak"], discovery.find("x").map(&:backend)
    assert_equal 0, github.searches
    discovery.define_singleton_method(:probe_flatpak) { |_| [] }
    assert_equal ["appimage"], discovery.find("x").map(&:backend)
    assert_equal 1, github.searches
  end

  def test_discovered_install_needs_confirmation_and_upgrades_from_saved_definition
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=cachyos\n"), host: fake_host(platform("ID=cachyos\n")))
    candidate = LinuxFormulas::Discovery::Candidate.new(
      backend: "flatpak", package_def: { "app_id" => "org.example.Tool", "remote" => "flathub" }, label: "Tool", detail: "",
    )
    app.discovery.define_singleton_method(:find) { |*| [candidate] }
    flatpak = app.backends.fetch("flatpak")
    calls = []
    flatpak.define_singleton_method(:installed?) { |*| false }
    flatpak.define_singleton_method(:install) { |definition, *| calls << [:install, definition["app_id"]]; true }
    flatpak.define_singleton_method(:upgrade) { |definition, *| calls << [:upgrade, definition["app_id"]]; true }

    original_stdin = $stdin
    $stdin = StringIO.new
    begin
      capture_io { assert_raises(SystemExit) { app.run(%w[install tool]) } }
    ensure
      $stdin = original_stdin
    end
    assert_empty calls

    capture_io { app.run(%w[install tool -y]) }
    assert app.state.get_installed("tool").dig("metadata", "discovered")
    capture_io { app.run(%w[upgrade tool]) }
    assert_equal [[:install, "org.example.Tool"], [:upgrade, "org.example.Tool"]], calls
  end

  def test_install_with_a_backend_the_manifest_dropped_can_still_be_removed
    os = platform("ID=cachyos\n")
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: os, host: fake_host(os))
    app.state.record_install("claude-code", "brew", metadata: { "package_definition" => { "cask" => "claude-code" } })
    out, = capture_io { app.run(%w[upgrade claude]) }
    assert_includes out, "[dry-run] brew upgrade --cask claude-code"
    out, = capture_io { app.run(%w[uninstall claude]) }
    assert_includes out, "[dry-run] brew uninstall --cask claude-code"
  end

  def test_upgrade_everything_runs_each_manager_once_and_continues_past_failures
    os = platform("ID=cachyos\n")
    app = LinuxFormulas::App.new(config_dir: @temp, platform: os, host: fake_host(os, aur_helper: "yay"))
    app.backends.fetch("flatpak").define_singleton_method(:available?) { true }
    app.state.record_install("moonlight", "flatpak")
    app.backends.fetch("flatpak").define_singleton_method(:upgrade) { |*| raise "covered by flatpak update" }
    commands = []
    app.define_singleton_method(:run_step) { |*cmd| commands << cmd.join(" "); cmd.first != "brew" }
    _, err = capture_io { assert_raises(SystemExit) { app.run(%w[upgrade -y]) } }
    assert_equal ["brew upgrade", "yay -Syu --noconfirm", "flatpak update -y"], commands
    assert_includes err, "Failed to upgrade: Homebrew"
  end

  def test_dry_run_upgrade_previews_pending_updates
    os = platform("ID=cachyos\n")
    host = fake_host(os, { "checkupdates" => "kwin 6.8.1-1 -> 6.8.1-2\n", "flatpak remote-ls --updates --columns=application,version" =>
                           "org.gnome.Platform\t\n" })
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: os, host: host)
    out, = capture_io { app.run(%w[upgrade]) }
    assert_includes out, "kwin"
    assert_includes out, "6.8.1-1 -> 6.8.1-2"
    assert_includes out, "org.gnome.Platform"
  end

  def test_system_view_reads_every_manager
    os = platform("ID=cachyos\n")
    host = fake_host(os, {
      "brew list --formula --installed-on-request" => "gh\n",
      "brew list --formula --versions" => "gh 2.102.0\nunzip 6.0_8\n",
      "brew list --cask --versions" => "claude-code 2.1.308\n",
      "pacman -Qmq" => "antigravity\n",
      "pacman -Qe" => "ark 26.08.2-1\nantigravity 2.26.0-1\n",
      "flatpak list --app --columns=application,name,version" => "com.moonlight_stream.Moonlight\tMoonlight\t6.2.0\n",
      "pacman -Q kwin" => "kwin 6.8.1-1\n",
    })
    installed = host.installed.map { |entry| [entry.source, entry.name] }
    assert_equal [%w[homebrew gh], %w[homebrew claude-code], %w[pacman ark], %w[aur antigravity], %w[flatpak Moonlight]], installed
    assert_equal "com.moonlight_stream.Moonlight", host.owners("moonlight").first.id
    assert_equal [%w[pacman kwin]], host.owners("kwin").map { |entry| [entry.source, entry.name] }
    assert_empty host.owners("missing")
  end

  def test_system_upgrade_command_per_distro
    arch = fake_host(platform("ID=cachyos\n"), aur_helper: "yay")
    assert_equal %w[yay -Syu], arch.system_upgrade_command
    assert_equal %w[yay -Syu --noconfirm], arch.system_upgrade_command(interactive: false)
    assert_equal %w[sudo dnf upgrade --refresh -y], fake_host(platform("ID=fedora\n")).system_upgrade_command(interactive: false)
    assert_equal nil, fake_host(platform("ID=debian\n")).system_upgrade_command
  end

  def test_unrecorded_packages_are_removed_and_upgraded_by_their_owner
    os = platform("ID=cachyos\n")
    host = fake_host(os, { "pacman -Qe" => "ark 26.08.2-1\n", "pacman -Q kwin" => "kwin 6.8.1-1\n" }, aur_helper: "yay")
    app = LinuxFormulas::App.new(config_dir: @temp, platform: os, host: host)
    commands = []
    app.define_singleton_method(:run_step) { |*cmd| commands << cmd.join(" "); true }
    capture_io { app.run(%w[uninstall ark]) }
    capture_io { app.run(%w[upgrade kwin]) }
    assert_equal ["sudo pacman -Rs ark", "yay -Syu"], commands
    _, err = capture_io { assert_raises(SystemExit) { app.run(%w[uninstall nothing-here]) } }
    assert_includes err, "not installed"
  end

  def test_appimage_install_upgrade_and_uninstall
    image = File.join(@temp, "tool.AppImage")
    File.write(image, "#!/bin/sh\necho tool\n")
    backend = release_backend(LinuxFormulas::Backends::AppImage, files: { "https://e.x/tool.AppImage" => image })
    pkg = LinuxFormulas::Package.new({ "name" => "tool" })
    definition = { "url" => "https://e.x/tool.AppImage", "sha256" => sha256(image), "version" => "1.0" }

    capture_io { assert backend.install(definition, pkg) }
    link = File.join(@temp, "bin", "tool")
    assert File.symlink?(link)
    assert File.executable?(File.readlink(link))
    assert backend.installed?(definition, pkg)
    out, = capture_io { assert backend.upgrade(definition, pkg) }
    assert_includes out, "already up to date"
    capture_io { assert backend.uninstall(definition, pkg) }
    refute File.symlink?(link)
    refute backend.installed?(definition, pkg)
  end

  def test_release_rejects_checksum_mismatch_and_foreign_links
    image = File.join(@temp, "tool.AppImage")
    File.write(image, "payload")
    backend = release_backend(LinuxFormulas::Backends::AppImage, files: { "https://e.x/tool.AppImage" => image })
    pkg = LinuxFormulas::Package.new({ "name" => "tool" })
    capture_io { refute backend.install({ "url" => "https://e.x/tool.AppImage", "sha256" => "0" * 64 }, pkg) }
    refute backend.installed?({}, pkg)

    FileUtils.mkdir_p(File.join(@temp, "bin"))
    File.write(File.join(@temp, "bin", "tool"), "user's own script")
    capture_io { refute backend.install({ "url" => "https://e.x/tool.AppImage", "sha256" => sha256(image) }, pkg) }
    assert_equal "user's own script", File.read(File.join(@temp, "bin", "tool"))
  end

  def test_archive_installs_github_release_and_upgrades_to_new_tag
    archives = %w[1.0 2.0].to_h do |version|
      root = File.join(@temp, "src-#{version}", "tool-#{version}")
      FileUtils.mkdir_p([File.join(root, "bin"), File.join(root, "lib")])
      File.write(File.join(root, "bin", "tool"), "#!/bin/sh\necho #{version}\n")
      File.chmod(0o755, File.join(root, "bin", "tool"))
      File.write(File.join(root, "lib", "libtool.so"), "")
      File.chmod(0o755, File.join(root, "lib", "libtool.so"))
      archive = File.join(@temp, "tool-#{version}-linux-x86_64.tar.gz")
      system("tar", "-czf", archive, "-C", File.dirname(root), File.basename(root), exception: true)
      [version, archive]
    end
    release = ->(version) do
      { "tag" => "v#{version}", "assets" => [{ "name" => File.basename(archives[version]), "url" => "https://e.x/#{version}",
                                               "sha256" => sha256(archives[version]) }] }
    end
    github = FakeGithub.new(release.call("1.0"))
    backend = release_backend(LinuxFormulas::Backends::Archive, github: github,
                                                                files: { "https://e.x/1.0" => archives["1.0"], "https://e.x/2.0" => archives["2.0"] })
    pkg = LinuxFormulas::Package.new({ "name" => "tool" })

    capture_io { assert backend.install({ "github" => "example/tool" }, pkg) }
    link = File.join(@temp, "bin", "tool")
    assert_includes File.read(link), "echo 1.0"
    github.release = release.call("2.0")
    capture_io { assert backend.upgrade({ "github" => "example/tool" }, pkg) }
    assert_includes File.read(link), "echo 2.0"
    assert_includes backend.info({}, pkg), '"version": "v2.0"'
  end
end

BackendsTest.instance_methods.grep(/^test_/).sort.each do |method|
  test = BackendsTest.new
  begin
    test.setup
    test.public_send(method)
    puts "PASS #{method}"
  ensure
    test.teardown
  end
end
