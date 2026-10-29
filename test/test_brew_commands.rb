# frozen_string_literal: true
# Run with `brew ruby -- test/test_brew_commands.rb` to exercise Homebrew's parser.
require "tmpdir"
require "stringio"
require_relative "../cmd/app"
require_relative "../cmd/linux"

Dir.mktmpdir do |config|
  previous = ENV["HOMEBREW_LINUX_FORMULAS_CONFIG_DIR"]
  ENV["HOMEBREW_LINUX_FORMULAS_CONFIG_DIR"] = config
  begin
    [Homebrew::Cmd::App, Homebrew::Cmd::Linux].each do |klass|
      %w[native pacman aur cask rpm dnf flatpak flathub brew tarball standalone appimage archive].each do |backend|
        klass.new(["install", "claude-desktop", "--#{backend}", "--dry-run", "--non-interactive"])
      end
      original_stdout = $stdout
      $stdout = StringIO.new
      begin
        klass.new(%w[install claude-desktop --backend=brew --dry-run --yes]).run
        raise "command lost arguments" unless $stdout.string.include?("[dry-run] brew install Brandon-Gottshall/linux-formulas/claude-desktop")
        raise "preview wrote install state" if File.exist?(File.join(config, "installed.json"))
      ensure
        $stdout = original_stdout
      end
    end
  ensure
    previous.nil? ? ENV.delete("HOMEBREW_LINUX_FORMULAS_CONFIG_DIR") : ENV["HOMEBREW_LINUX_FORMULAS_CONFIG_DIR"] = previous
  end
end
puts "Homebrew command parser tests passed."
