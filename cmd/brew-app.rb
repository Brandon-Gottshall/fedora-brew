# typed: false
# frozen_string_literal: true

require "abstract_command"
require_relative "../lib/linux_formulas/app"

module Homebrew
  module Cmd
    class App < AbstractCommand
      cmd_args do
        usage_banner "`app` [<subcommand>] [<package>] [<options>]"
        description "Manage Linux applications through RPM, pacman, AUR, Flatpak, or Homebrew."
        switch "--dry-run", description: "Preview commands without installing or changing package state."
        switch "-y", "--yes", description: "Run without interactive backend selection."
        switch "--non-interactive", description: "Run without interactive backend selection."
        %w[native pacman aur cask rpm dnf flatpak flathub brew tarball standalone appimage archive].each do |backend|
          switch "--#{backend}", description: "Select the #{backend} installation method."
        end
        flag "--backend=", description: "Select an installation backend by name."
        named_args :string
      end

      def initialize(argv = ARGV.freeze)
        @app_argv = argv.dup
        super(argv)
      end

      def run
        LinuxFormulas::App.new.run(@app_argv.dup)
      end
    end
  end
end
