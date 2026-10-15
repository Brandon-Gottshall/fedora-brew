# frozen_string_literal: true

require_relative "pacman"

module LinuxFormulas
  module Backends
    class Aur < Pacman
      # Any pacman-compatible helper can be configured as a single executable
      # name/path. Never execute the helper through sudo (makepkg rejects root).
      def initialize(dry_run: false, helper: nil)
        super(dry_run: dry_run)
        @configured_helper = helper || ENV["LINUX_FORMULAS_AUR_HELPER"]
      end

      def name
        "aur"
      end

      def available?
        !helper.nil?
      end

      def install(package_def, manifest, options = {})
        selected = helper
        unless selected
          warn "No AUR helper found. Install a pacman-compatible helper or set LINUX_FORMULAS_AUR_HELPER to its executable."
          return false
        end
        execute_command(selected, "-Syu", "--needed", *confirmation(options), package_def["package"] || manifest.name)
      end

      def info(package_def, manifest)
        selected = helper
        selected ? command_output(selected, "-Si", package_def["package"] || manifest.name) : "No AUR helper found."
      end

      private

      def helper
        if @configured_helper && !@configured_helper.empty?
          return @configured_helper if binary_exists?(@configured_helper)
          return nil
        end
        %w[paru yay].find { |candidate| binary_exists?(candidate) }
      end
    end
  end
end
