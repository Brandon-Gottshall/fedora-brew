# frozen_string_literal: true

require_relative "base"

module FedoraBrew
  module Backends
    class Pacman < Base
      def name
        "pacman"
      end

      def available?
        binary_exists?("pacman")
      end

      def installed?(package_def, manifest)
        system("pacman", "-Q", package_def["package"] || manifest.name, out: File::NULL, err: File::NULL)
      end

      def install(package_def, manifest, options = {})
        # Refresh and upgrade together: Arch does not support partial upgrades.
        execute_command("sudo", "pacman", "-Syu", "--needed", *confirmation(options), package_def["package"] || manifest.name)
      end

      def upgrade(package_def, manifest, options = {})
        install(package_def, manifest, options)
      end

      def uninstall(package_def, manifest, options = {})
        execute_command("sudo", "pacman", "-R", *confirmation(options), package_def["package"] || manifest.name)
      end

      def info(package_def, manifest)
        command_output("pacman", "-Si", package_def["package"] || manifest.name)
      end

      protected

      def confirmation(options)
        options[:interactive] == false ? ["--noconfirm"] : []
      end
    end
  end
end
