# frozen_string_literal: true

require_relative "base"

module LinuxFormulas
  module Backends
    class Brew < Base
      def name
        "brew"
      end

      def available?
        binary_exists?("brew")
      end

      def installed?(package_def, manifest)
        ref, type_args = package_reference(package_def, manifest)
        system("brew", "list", *type_args, ref, out: File::NULL, err: File::NULL)
      end

      def install(package_def, manifest, _options = {})
        ref, type_args = package_reference(package_def, manifest)
        puts "==> Installing #{manifest.display_name} via Homebrew (#{ref})..."
        execute_command("brew", "install", *type_args, ref)
      end

      def upgrade(package_def, manifest, _options = {})
        ref, type_args = package_reference(package_def, manifest)
        puts "==> Upgrading #{manifest.display_name} via Homebrew (#{ref})..."
        execute_command("brew", "upgrade", *type_args, ref)
      end

      def uninstall(package_def, manifest, _options = {})
        ref, type_args = package_reference(package_def, manifest)
        puts "==> Uninstalling #{manifest.display_name} via Homebrew (#{ref})..."
        execute_command("brew", "uninstall", *type_args, ref)
      end

      def info(package_def, manifest)
        ref, type_args = package_reference(package_def, manifest)
        command_output("brew", "info", *type_args, ref)
      end

      private

      def package_reference(package_def, manifest)
        if package_def["cask"]
          [package_def["cask"], ["--cask"]]
        else
          [package_def["formula"] || manifest.name, []]
        end
      end
    end
  end
end
