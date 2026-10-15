# frozen_string_literal: true
require "stringio"
require "tmpdir"
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
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=arch\n"))
    app.state.record_install("removed-package", "pacman")
    out, = capture_io { app.run(%w[uninstall removed-package]) }
    assert_includes out, "sudo pacman -R removed-package"
  end

  def test_success_records_platform_and_failed_install_does_not
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=cachyos\n"))
    backend = app.backends.fetch("pacman")
    backend.define_singleton_method(:install) { |*| false }
    capture_io { assert_raises(SystemExit) { app.run(%w[install jump-desktop --pacman]) } }
    assert_empty app.state.installed
    backend.define_singleton_method(:install) { |*| true }
    capture_io { app.run(%w[install jump-desktop --pacman]) }
    assert_equal "arch", app.state.get_installed("jump-desktop").dig("metadata", "distro")
  end

  def test_lifecycle_uses_canonical_catalog_name
    app = LinuxFormulas::App.new(config_dir: @temp, platform: platform("ID=arch\n"))
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
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=arch\n"))
    app.state.record_install("removed-package", "aur", metadata: {"package_definition" => {"package" => "real-package-bin"}})
    out, = capture_io { app.run(%w[uninstall removed-package]) }
    assert_includes out, "sudo pacman -R real-package-bin"
    refute_includes out, "sudo pacman -R removed-package"
    capture_io { assert_raises(SystemExit) { app.run(%w[upgrade]) } }
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
    app = LinuxFormulas::App.new(dry_run: true, config_dir: @temp, platform: platform("ID=cachyos\n"))
    capture_io { app.run(%w[install jump-desktop --pacman --yes]) }
    assert_empty app.state.installed
    refute File.exist?(app.state.state_file)
    app.state.record_install("jump-desktop", "pacman")
    original = File.read(app.state.state_file)
    capture_io { app.run(%w[uninstall jump-desktop]) }
    assert_equal original, File.read(app.state.state_file)
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
