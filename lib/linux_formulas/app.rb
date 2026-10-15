# frozen_string_literal: true

require_relative "state"
require_relative "catalog"
require_relative "resolver"
require_relative "backends/rpm"
require_relative "backends/flatpak"
require_relative "backends/brew"
require_relative "backends/pacman"
require_relative "backends/aur"

module LinuxFormulas
  class App
    attr_reader :state, :catalog, :resolver, :backends, :dry_run

    def initialize(dry_run: false, packages_dir: nil, config_dir: nil, platform: Platform.new)
      @dry_run = dry_run
      @state = State.new(config_dir: config_dir, platform: platform)
      @catalog = Catalog.new(packages_dir: packages_dir, platform: platform)
      @resolver = Resolver.new(state: @state)
      @backends = {
        "rpm" => Backends::Rpm.new(dry_run: dry_run),
        "pacman" => Backends::Pacman.new(dry_run: dry_run),
        "aur" => Backends::Aur.new(dry_run: dry_run, helper: @state.config["aur_helper"]),
        "flatpak" => Backends::Flatpak.new(dry_run: dry_run),
        "brew" => Backends::Brew.new(dry_run: dry_run),
      }
    end

    def run(args)
      command = args.shift || "help"
      options = parse_options(args)

      case command
      when "install", "i"
        cmd_install(options)
      when "upgrade", "update", "up"
        cmd_upgrade(options)
      when "uninstall", "remove", "rm"
        cmd_uninstall(options)
      when "list", "ls"
        cmd_list(options)
      when "info", "show"
        cmd_info(options)
      when "config"
        cmd_config(options)
      when "doctor"
        cmd_doctor(options)
      when "help", "--help", "-h"
        cmd_help
      else
        warn "Unknown command: #{command}"
        cmd_help
        exit 1
      end
    end

    private

    def parse_options(args)
      options = {
        package_name: nil,
        backend: nil,
        interactive: true,
        dry_run: @dry_run,
        extra: [],
      }

      while (arg = args.shift)
        case arg
        when "--dry-run"
          options[:dry_run] = true
          @dry_run = true
          @backends.each_value { |b| b.instance_variable_set(:@dry_run, true) }
        when "-y", "--yes", "--non-interactive"
          options[:interactive] = false
        when "--native"
          options[:backend] = "native"
        when "--pacman", "--aur"
          options[:backend] = arg.delete_prefix("--")
        when "--cask"
          options[:backend] = "brew"
        when "--rpm", "--dnf"
          options[:backend] = "rpm"
        when "--flatpak", "--flathub"
          options[:backend] = "flatpak"
        when "--brew", "--tarball", "--standalone"
          options[:backend] = "brew"
        when /^--backend=(.+)$/
          options[:backend] = Regexp.last_match(1)
        else
          if options[:package_name].nil? && !arg.start_with?("-")
            options[:package_name] = arg
          else
            options[:extra] << arg
          end
        end
      end

      options
    end

    def cmd_install(opts)
      name = opts[:package_name]
      unless name
        warn "Usage: brew app install <package> [--rpm|--pacman|--aur|--flatpak|--brew] [--dry-run]"
        exit 1
      end

      package = catalog.find(name)
      unless package
        warn "Error: Package '#{name}' not found in catalog."
        warn "Available packages: #{catalog.all.map(&:name).join(', ')}"
        exit 1
      end

      backend_name = resolver.resolve(package, explicit_backend: opts[:backend], interactive: opts[:interactive])
      backend = backends[backend_name]
      unless backend
        warn "Error: Unsupported backend '#{backend_name}'."
        exit 1
      end

      puts "==> Installing #{package.display_name} using #{backend_name.upcase} backend..."
      success = backend.install(package.backend(backend_name), package, opts)

      if success
        state.record_install(package.name, backend_name, metadata: { "display_name" => package.display_name, "distro" => state.platform.family, "package_definition" => package.backend(backend_name) }) unless dry_run
        puts dry_run ? "\nPreview complete for #{package.display_name} via #{backend_name.upcase}." : "\n✔ Successfully installed #{package.display_name} via #{backend_name.upcase}."
      else
        warn "\n✖ Installation of #{package.display_name} failed."
        exit 1
      end
    end

    def cmd_upgrade(opts)
      name = opts[:package_name]
      if name
        package = catalog.find(name)
        unless package
          warn "Error: Package '#{name}' not found in catalog."
          exit 1
        end

        name = package.name
        installed_info = state.get_installed(name)
        backend_name = resolver.resolve(package, explicit_backend: opts[:backend] || installed_info&.dig("backend"), interactive: false)
        backend = backends[backend_name]
        unless backend
          warn "Error: Backend '#{backend_name}' not available for #{name}."
          exit 1
        end

        puts "==> Upgrading #{package.display_name} via #{backend_name.upcase}..."
        exit 1 unless backend.upgrade(package.backend(backend_name), package, opts)
      else
        puts "==> Upgrading all managed applications..."
        state.installed.each do |pkg_name, info|
          pkg = catalog.find(pkg_name)
          unless pkg
            warn "Error: Manifest for managed package '#{pkg_name}' is missing; restore it before upgrading."
            exit 1
          end

          b_name = info["backend"]
          b = backends[b_name]
          if b && pkg.has_backend?(b_name)
            puts "--> Upgrading #{pkg.display_name} (#{b_name})..."
            exit 1 unless b.upgrade(pkg.backend(b_name), pkg, opts)
          else
            warn "Error: Recorded backend '#{b_name}' for #{pkg_name} is unavailable on this platform."
            exit 1
          end
        end
      end
    end

    def cmd_uninstall(opts)
      name = opts[:package_name]
      unless name
        warn "Usage: brew app uninstall <package> [--dry-run]"
        exit 1
      end

      package = catalog.find(name)
      name = package.name if package
      installed_info = state.get_installed(name)

      backend_name = opts[:backend] || installed_info&.dig("backend")
      if package
        backend_name = resolver.resolve(package, explicit_backend: backend_name, interactive: false)
      elsif backend_name
        backend_name = resolver.normalize_backend(backend_name)
      end

      unless backend_name && backends[backend_name]
        warn "Error: Could not determine backend for '#{name}'."
        exit 1
      end

      pkg_def = if package
        package.backend(backend_name)
      else
        installed_info&.dig("metadata", "package_definition") || { "package" => name, "app_id" => name, "formula" => name }
      end
      display = package ? package.display_name : name

      puts "==> Uninstalling #{display} from #{backend_name.upcase} backend..."
      success = backends[backend_name].uninstall(pkg_def, package || Package.new({ "name" => name }), opts)

      if success
        state.record_uninstall(name) unless dry_run
        puts dry_run ? "\nRemoval preview complete for #{display}." : "\n✔ Successfully uninstalled #{display}."
      else
        exit 1
      end
    end

    def cmd_list(_opts)
      installed = state.installed
      all_catalog = catalog.all

      puts "Installed Managed Applications:"
      if installed.empty?
        puts "  (None managed yet. Use 'brew app install <name>' to install)"
      else
        installed.each do |pkg_name, info|
          pkg = catalog.find(pkg_name)
          display = pkg ? pkg.display_name : pkg_name
          puts "  • #{display} [#{info['backend']}] (installed #{info['installed_at']})"
        end
      end

      puts "\nAvailable Catalog Packages:"
      all_catalog.each do |pkg|
        status = installed.key?(pkg.name) ? " [Installed: #{installed[pkg.name]['backend']}]" : ""
        puts "  • #{pkg.name.ljust(15)} - #{pkg.display_name} (backends: #{pkg.backend_names.join(', ')})#{status}"
      end
    end

    def cmd_info(opts)
      name = opts[:package_name]
      unless name
        warn "Usage: brew app info <package>"
        exit 1
      end

      package = catalog.find(name)
      unless package
        warn "Error: Package '#{name}' not found."
        exit 1
      end

      installed_info = state.get_installed(name)

      puts "=================================================="
      puts "  #{package.display_name} (#{package.name})"
      puts "=================================================="
      puts "Description: #{package.description}"
      puts "Homepage:    #{package.homepage}"
      puts "Status:      #{installed_info ? "Installed via #{installed_info['backend']}" : 'Not installed'}"
      puts "Default:     #{package.default_backend}"
      puts "\nAvailable Backends:"
      package.backends.each do |b_name, b_info|
        puts "  [#{b_name.upcase}]"
        puts "    Summary: #{b_info['summary']}" if b_info["summary"]
        if b_info["pros"]
          b_info["pros"].each { |p| puts "    + #{p}" }
        end
        if b_info["cons"]
          b_info["cons"].each { |c| puts "    - #{c}" }
        end
      end
      puts "=================================================="
    end

    def cmd_config(opts)
      key = opts[:package_name] # First arg after config
      value = opts[:extra].first

      if key.nil?
        puts "Current Configuration:"
        puts JSON.pretty_generate(state.config)
      elsif value.nil?
        puts "#{key} = #{state.config[key]}"
      else
        state.set_config(key, value)
        puts "Set #{key} = #{value}"
      end
    end

    def cmd_doctor(_opts)
      doctor_script = File.expand_path("../../scripts/doctor", __dir__)
      if File.exist?(doctor_script)
        system(doctor_script)
      else
        puts "Doctor script not found."
      end
    end

    def cmd_help
      puts <<~HELP
        Linux Formulas App Manager (Catalog & Multi-Backend Resolver)

        Usage:
          brew app install <package> [options]    Install application with backend choice
          brew app upgrade [package]              Upgrade installed application(s)
          brew app uninstall <package>            Uninstall application
          brew app list                           List installed & available packages
          brew app info <package>                 Show package details and backends
          brew app config [key] [value]           View or set global preferences
          brew app doctor                         Run diagnostic checks

        Backend Selection Options:
          --native                Use the host distro native backend
          --rpm, --dnf            Force Fedora RPM / DNF backend
          --pacman                Force Arch repository backend
          --aur                   Use a configured or detected AUR helper
          --flatpak               Force Flathub Flatpak backend
          --brew, --tarball       Force Homebrew formula / tarball backend
          --backend=<name>        Specify backend explicitly
          --dry-run               Preview commands without modifying system
          -y, --yes               Non-interactive mode (use defaults)

        Examples:
          brew app install antigravity
          brew app install antigravity --flatpak
          brew app install flare --rpm
          brew app config default_backend flatpak
      HELP
    end
  end
end
