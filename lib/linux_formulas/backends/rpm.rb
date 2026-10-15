# frozen_string_literal: true

require_relative "base"

module LinuxFormulas
  module Backends
    class Rpm < Base
      def name
        "rpm"
      end

      def available?
        binary_exists?("dnf") || binary_exists?("rpm")
      end

      def installed?(package_def, _manifest)
        pkg = package_def["package"] || _manifest.name
        system("rpm -q #{pkg} >/dev/null 2>&1")
      end

      def install(package_def, manifest, _options = {})
        pkg = package_def["package"] || manifest.name

        # Configure repository if specified
        if package_def["copr"]
          copr_repo = package_def["copr"]
          puts "==> Enabling COPR repository: #{copr_repo}"
          return false unless execute_command("sudo", "dnf", "copr", "enable", "-y", copr_repo)
        elsif package_def["repo"]
          repo_config = package_def["repo"]
          repo_name = repo_config["name"]
          repo_url = repo_config["baseurl"]
          gpgcheck = repo_config.fetch("gpgcheck", 1)

          repo_file = "/etc/yum.repos.d/#{repo_name}.repo"
          unless File.exist?(repo_file) || @dry_run
            puts "==> Adding DNF repository: #{repo_name}"
            content = <<~REPO
              [#{repo_name}]
              name=#{repo_name}
              baseurl=#{repo_url}
              enabled=1
              gpgcheck=#{gpgcheck}
            REPO
            tmp_file = "/tmp/#{repo_name}.repo"
            File.write(tmp_file, content)
            execute_command("sudo", "mv", tmp_file, repo_file)
            execute_command("sudo", "chmod", "644", repo_file)
          end
        end

        puts "==> Installing #{pkg} via DNF..."
        execute_command("sudo", "dnf", "install", "-y", pkg)
      end

      def upgrade(package_def, manifest, _options = {})
        pkg = package_def["package"] || manifest.name
        puts "==> Upgrading #{pkg} via DNF..."
        execute_command("sudo", "dnf", "upgrade", "-y", pkg)
      end

      def uninstall(package_def, manifest, _options = {})
        pkg = package_def["package"] || manifest.name
        puts "==> Removing #{pkg} via DNF..."
        execute_command("sudo", "dnf", "remove", "-y", pkg)
      end

      def info(package_def, manifest)
        pkg = package_def["package"] || manifest.name
        command_output("rpm", "-qi", pkg)
      end
    end
  end
end
