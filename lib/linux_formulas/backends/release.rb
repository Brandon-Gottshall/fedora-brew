# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "tmpdir"
require "uri"
require_relative "base"
require_relative "../github"

module LinuxFormulas
  module Backends
    # Installs a downloaded release artifact under the user's data directory and
    # links its executable into ~/.local/bin. A package definition either pins a
    # `url` (+ `sha256`) or names a `github` repository whose latest release is
    # used; `asset` (regex) and `binary` narrow the asset and executable choice.
    # A receipt next to the install lets upgrades detect newer releases.
    class Release < Base
      RECEIPT = ".linux-formulas.json"

      def initialize(dry_run: false, github: Github.new, apps_dir: nil, bin_dir: nil)
        super(dry_run: dry_run)
        @github = github
        data_home = ENV["XDG_DATA_HOME"].to_s.empty? ? File.join(Dir.home, ".local", "share") : ENV["XDG_DATA_HOME"]
        # Homebrew only passes HOMEBREW_-prefixed variables through to commands.
        @apps_dir = apps_dir || ENV["HOMEBREW_LINUX_FORMULAS_APPS_DIR"] || ENV["LINUX_FORMULAS_APPS_DIR"] ||
                    File.join(data_home, "linux-formulas", "apps")
        @bin_dir = bin_dir || ENV["HOMEBREW_LINUX_FORMULAS_BIN_DIR"] || ENV["LINUX_FORMULAS_BIN_DIR"] ||
                   File.join(Dir.home, ".local", "bin")
      end

      def available?
        binary_exists?("curl")
      end

      def installed?(_package_def, manifest)
        File.file?(receipt_path(manifest))
      end

      def install(package_def, manifest, _options = {})
        artifact = resolve(package_def)
        artifact ? deploy(package_def, manifest, artifact) : false
      end

      def upgrade(package_def, manifest, _options = {})
        artifact = resolve(package_def)
        return false unless artifact

        receipt = read_receipt(manifest)
        if receipt && receipt["url"] == artifact["url"] &&
           (artifact["sha256"].nil? || receipt["sha256"] == artifact["sha256"])
          puts "==> #{manifest.display_name} is already up to date (#{artifact['version']})."
          return true
        end
        deploy(package_def, manifest, artifact)
      end

      def uninstall(_package_def, manifest, _options = {})
        target = app_dir(manifest)
        link = read_receipt(manifest)&.dig("link")
        if dry_run
          puts "[dry-run] remove #{target}#{link ? " and #{link}" : ''}"
          return true
        end
        File.unlink(link) if link && File.symlink?(link) && File.readlink(link).start_with?("#{target}/")
        FileUtils.rm_rf(target)
        true
      end

      def info(_package_def, manifest)
        receipt = read_receipt(manifest)
        receipt ? JSON.pretty_generate(receipt) : "Not installed."
      end

      protected

      def kind
        raise NotImplementedError
      end

      # Copy or unpack `download` into `staging`; return the executable's path
      # relative to `staging`, or nil when none can be identified.
      def place(_download, _staging, _package_def, _manifest)
        raise NotImplementedError
      end

      def link_name(_package_def, manifest, _executable)
        manifest.name
      end

      def fetch(url, destination)
        execute_command("curl", "-fL", "--retry", "3", "--proto", "=https", "-o", destination, url)
      end

      private

      def app_dir(manifest)
        File.join(@apps_dir, manifest.name)
      end

      def receipt_path(manifest)
        File.join(app_dir(manifest), RECEIPT)
      end

      def read_receipt(manifest)
        JSON.parse(File.read(receipt_path(manifest)))
      rescue StandardError
        nil
      end

      def resolve(package_def)
        if package_def["url"]
          return {
            "url" => package_def["url"],
            "sha256" => package_def["sha256"],
            "version" => package_def["version"] || "pinned",
            "asset" => File.basename(URI(package_def["url"]).path),
          }
        end

        repository = package_def["github"]
        unless repository
          warn "Error: #{name} package definitions need a `url` or a `github` repository."
          return nil
        end
        release = @github.latest_release(repository)
        asset = release && @github.select_asset(release["assets"], kind, pattern: package_def["asset"])
        unless asset
          warn "Error: no #{kind} asset for this machine in #{repository}'s latest release."
          return nil
        end
        { "url" => asset["url"], "sha256" => asset["sha256"], "version" => release["tag"], "asset" => asset["name"] }
      end

      def deploy(package_def, manifest, artifact)
        target = app_dir(manifest)
        if dry_run
          puts "[dry-run] download #{artifact['url']}"
          puts "[dry-run] install #{artifact['asset']} (#{artifact['version']}) into #{target}"
          return true
        end

        FileUtils.mkdir_p(@apps_dir)
        Dir.mktmpdir(".staging-#{manifest.name}-", @apps_dir) do |work|
          download = File.join(work, artifact["asset"])
          return false unless fetch(artifact["url"], download)

          digest = Digest::SHA256.file(download).hexdigest
          if artifact["sha256"] && digest != artifact["sha256"].downcase
            warn "Error: checksum mismatch for #{artifact['asset']} (expected #{artifact['sha256']}, got #{digest})."
            return false
          end
          warn "Warning: #{artifact['asset']} has no published checksum; recording #{digest}." unless artifact["sha256"]

          staging = File.join(work, "app")
          FileUtils.mkdir_p(staging)
          executable = place(download, staging, package_def, manifest)
          return false unless executable

          link = File.join(@bin_dir, link_name(package_def, manifest, executable))
          return false unless link_free?(link, target)

          File.write(File.join(staging, RECEIPT), JSON.pretty_generate(
            "name" => manifest.name, "kind" => kind, "version" => artifact["version"],
            "url" => artifact["url"], "asset" => artifact["asset"], "sha256" => digest,
            "executable" => executable, "link" => link, "installed_at" => Time.now.utc.iso8601,
          ))
          previous = File.join(work, "previous")
          File.rename(target, previous) if File.exist?(target)
          File.rename(staging, target)

          FileUtils.mkdir_p(@bin_dir)
          File.unlink(link) if File.symlink?(link)
          File.symlink(File.join(target, executable), link)
          puts "==> Installed #{manifest.display_name} #{artifact['version']}; linked #{link}"
        end
        true
      end

      # Never replace a file or link that this backend did not create.
      def link_free?(link, target)
        return true unless File.exist?(link) || File.symlink?(link)
        return true if File.symlink?(link) && File.readlink(link).start_with?("#{target}/")

        warn "Error: #{link} already exists and is not managed by linux-formulas; remove it or set `binary`."
        false
      end
    end

    class AppImage < Release
      def name
        "appimage"
      end

      protected

      def kind
        "appimage"
      end

      def place(download, staging, _package_def, manifest)
        executable = "#{manifest.name}.AppImage"
        FileUtils.cp(download, File.join(staging, executable))
        File.chmod(0o755, File.join(staging, executable))
        executable
      end

      def link_name(package_def, manifest, _executable)
        package_def["binary"] || manifest.name
      end
    end

    class Archive < Release
      def name
        "archive"
      end

      def available?
        super && binary_exists?("tar")
      end

      protected

      def kind
        "archive"
      end

      def place(download, staging, package_def, manifest)
        return nil unless execute_command("tar", "-xf", download, "-C", staging)

        executables = Dir.glob(File.join(staging, "**", "*")).select do |path|
          File.file?(path) && !File.symlink?(path) && File.executable?(path) && !path.match?(/\.(so(\.\d+)*|sh|py|desktop)\z/)
        end
        relative = executables.map { |path| path.delete_prefix("#{staging}/") }
        wanted = package_def["binary"]
        chosen = if wanted
          relative.select { |path| File.basename(path) == wanted }
        else
          by_name = relative.select { |path| File.basename(path).casecmp?(manifest.name) }
          by_name.empty? ? relative : by_name
        end
        chosen = chosen.select { |path| File.basename(File.dirname(path)) == "bin" } if chosen.length > 1
        return chosen.first if chosen.length == 1

        warn "Error: could not pick the executable in #{File.basename(download)}" \
             "#{relative.empty? ? '' : " (candidates: #{relative.first(8).join(', ')})"}; set `binary` in the package definition."
        nil
      end

      def link_name(package_def, _manifest, executable)
        package_def["binary"] || File.basename(executable)
      end
    end
  end
end
