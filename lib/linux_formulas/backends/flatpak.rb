# frozen_string_literal: true

require_relative "base"

module LinuxFormulas
  module Backends
    class Flatpak < Base
      def name
        "flatpak"
      end

      def available?
        binary_exists?("flatpak")
      end

      def installed?(package_def, _manifest)
        app_id = package_def["app_id"]
        return false unless app_id

        system("flatpak info #{app_id} >/dev/null 2>&1")
      end

      def install(package_def, manifest, _options = {})
        app_id = package_def["app_id"]
        remote = package_def["remote"] || "flathub"

        # Ensure Flathub remote exists if needed
        if remote == "flathub"
          puts "==> Ensuring Flathub remote is configured..."
          execute_command("flatpak", "remote-add", "--if-not-exists", "--user", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo")
        end

        puts "==> Installing #{manifest.display_name} (#{app_id}) via Flatpak..."
        execute_command("flatpak", "install", "-y", "--user", remote, app_id)
      end

      def upgrade(package_def, manifest, _options = {})
        app_id = package_def["app_id"]
        puts "==> Upgrading #{manifest.display_name} (#{app_id}) via Flatpak..."
        execute_command("flatpak", "update", "-y", app_id)
      end

      def uninstall(package_def, manifest, _options = {})
        app_id = package_def["app_id"]
        puts "==> Uninstalling #{manifest.display_name} (#{app_id}) via Flatpak..."
        execute_command("flatpak", "uninstall", "-y", app_id)
      end

      def info(package_def, _manifest)
        app_id = package_def["app_id"]
        command_output("flatpak", "info", app_id)
      end
    end
  end
end
