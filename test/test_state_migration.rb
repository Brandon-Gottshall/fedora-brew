# frozen_string_literal: true
require "tmpdir"
require_relative "../lib/linux_formulas/state"

keys = %w[XDG_CONFIG_HOME HOMEBREW_LINUX_FORMULAS_CONFIG_DIR LINUX_FORMULAS_CONFIG_DIR HOMEBREW_FEDORA_BREW_CONFIG_DIR FEDORA_BREW_CONFIG_DIR]
saved = keys.to_h { |key| [key, ENV[key]] }
begin
  keys.each { |key| ENV.delete(key) }
  Dir.mktmpdir do |root|
    ENV["XDG_CONFIG_HOME"] = root
    legacy = File.join(root, "fedora-brew")
    FileUtils.mkdir_p(legacy)
    File.write(File.join(legacy, "config.json"), '{"default_backend":"flatpak"}')
    File.write(File.join(legacy, "installed.json"), '{"vicinae":{"backend":"brew"}}')
    state = LinuxFormulas::State.new
    raise "wrong destination" unless state.config_dir == File.join(root, "linux-formulas")
    raise "preference lost" unless state.config["default_backend"] == "flatpak"
    raise "install record lost" unless state.get_installed("vicinae")["backend"] == "brew"
    raise "legacy removed" unless File.file?(File.join(legacy, "installed.json"))
    state.set_config("default_backend", "brew")
    raise "new state overwritten" unless LinuxFormulas::State.new.config["default_backend"] == "brew"
    ENV["FEDORA_BREW_CONFIG_DIR"] = legacy
    raise "legacy override ignored" unless LinuxFormulas::State.new.config_dir == legacy
    ENV["LINUX_FORMULAS_CONFIG_DIR"] = File.join(root, "explicit")
    explicit = LinuxFormulas::State.new
    raise "new override not preferred" unless explicit.config_dir == ENV["LINUX_FORMULAS_CONFIG_DIR"]
    raise "explicit path unexpectedly migrated" unless explicit.installed.empty?
  end
ensure
  saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
end
puts "State migration tests passed."
