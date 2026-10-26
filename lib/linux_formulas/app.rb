# frozen_string_literal: true

require_relative "state"
require_relative "catalog"
require_relative "resolver"
require_relative "backends/rpm"
require_relative "backends/flatpak"
require_relative "backends/brew"
require_relative "backends/pacman"
require_relative "backends/aur"
require_relative "backends/release"
require_relative "discovery"
require_relative "system"

module LinuxFormulas
  class App
    SOURCE_TITLES = {
      "homebrew" => "Homebrew", "pacman" => "Pacman (repositories)", "aur" => "AUR / foreign",
      "rpm" => "DNF / RPM", "flatpak" => "Flatpak", "appimage" => "AppImage", "archive" => "Release archives",
    }.freeze
    NATIVE_SOURCES = %w[pacman aur rpm].freeze

    attr_reader :state, :catalog, :resolver, :backends, :discovery, :host, :dry_run

    def initialize(dry_run: false, packages_dir: nil, config_dir: nil, platform: Platform.new, github: Github.new, host: nil)
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
        "appimage" => Backends::AppImage.new(dry_run: dry_run, github: github),
        "archive" => Backends::Archive.new(dry_run: dry_run, github: github),
      }
      @discovery = Discovery.new(backends: @backends, github: github)
      @host = host || System.new(platform: platform, aur_helper: @state.config["aur_helper"], apps_dir: @backends["appimage"].apps_dir)
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
      when "outdated"
        cmd_outdated(options)
      when "info", "show"
        cmd_info(options)
      when "search"
        cmd_search(options)
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
        when "--appimage", "--archive"
          options[:backend] = arg.delete_prefix("--")
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
        warn "Usage: brew app install <package> [--rpm|--pacman|--aur|--flatpak|--brew|--appimage|--archive] [--dry-run]"
        exit 1
      end

      package = catalog.find(name)
      return install_discovered(name, opts) unless package

      begin
        backend_name = resolver.resolve(package, explicit_backend: opts[:backend], interactive: opts[:interactive])
      rescue Resolver::Cancelled
        warn "\nCancelled; nothing was installed."
        exit 1
      end
      perform_install(package, backend_name, package.backend(backend_name), opts)
    end

    def perform_install(package, backend_name, package_def, opts, discovered: false)
      backend = backends[backend_name]
      unless backend
        warn "Error: Unsupported backend '#{backend_name}'."
        exit 1
      end

      # Adopt an existing install (e.g. a system-wide Flatpak) instead of
      # installing a second copy alongside it.
      if backend.installed?(package_def, package)
        puts "==> #{package.display_name} is already installed via #{backend_name.upcase}; adopting it."
        success = true
      else
        puts "==> Installing #{package.display_name} using #{backend_name.upcase} backend..."
        success = backend.install(package_def, package, opts)
      end

      if success
        metadata = { "display_name" => package.display_name, "distro" => state.platform.family, "package_definition" => package_def }
        metadata["discovered"] = true if discovered
        state.record_install(package.name, backend_name, metadata: metadata) unless dry_run
        puts dry_run ? "\nPreview complete for #{package.display_name} via #{backend_name.upcase}." : "\n✔ Successfully installed #{package.display_name} via #{backend_name.upcase}."
      else
        warn "\n✖ Installation of #{package.display_name} failed."
        exit 1
      end
    end

    # A name outside the catalog: an exact Homebrew formula/cask installs as
    # usual (Homebrew keeps it updated); otherwise offer exact matches from
    # Flathub, pacman, the AUR and GitHub releases and install the confirmed one.
    def install_discovered(name, opts)
      only = opts[:backend] && resolver.normalize_backend(opts[:backend])
      if only.nil? || only == "brew"
        homebrew = discovery.homebrew_match(name)
        if homebrew
          puts "==> '#{name}' is a #{homebrew.detail}"
          package = Package.new({ "name" => name.downcase, "display_name" => homebrew.label })
          brew = backends.fetch("brew")
          if brew.installed?(homebrew.package_def, package)
            puts "==> #{homebrew.label} is already installed with Homebrew; `brew upgrade` keeps it current."
            return
          end
          exit 1 unless brew.install(homebrew.package_def, package, opts)
          return
        end
        if only == "brew"
          warn "Error: Homebrew has no formula or Linux cask named '#{name}'."
          exit 1
        end
      end

      puts "==> '#{name}' is not in the catalog or Homebrew; looking for exact matches..."
      candidates = discovery.find(name, only: only)
      if candidates.empty?
        warn "Error: no exact match for '#{name}' on Homebrew, Flathub, pacman, the AUR or GitHub releases."
        exit 1
      end

      puts "\nFound:"
      candidates.each_with_index do |candidate, index|
        puts "  #{index + 1}) #{candidate.backend.upcase.ljust(8)} #{candidate.label}"
        puts "     #{candidate.detail}"
      end
      choice = choose_candidate(candidates, opts)
      unless choice
        warn "Cancelled; nothing was installed."
        exit 1
      end

      package = Package.new({ "name" => name.downcase, "display_name" => choice.label })
      perform_install(package, choice.backend, choice.package_def, opts, discovered: true)
    end

    def choose_candidate(candidates, opts)
      return candidates.first if dry_run || !opts[:interactive]
      unless $stdin.tty?
        warn "Confirmation required: rerun with -y to install #{candidates.first.label} (#{candidates.first.backend})."
        return nil
      end

      range = candidates.length > 1 ? "1-#{candidates.length}, " : ""
      loop do
        print "\nInstall 1) #{candidates.first.label}? [#{range}Enter = 1, q = cancel]: "
        input = $stdin.gets
        return nil if input.nil?

        input = input.strip.downcase
        return candidates.first if input.empty? || input == "y"
        return nil if %w[q quit n no cancel].include?(input)
        return candidates[input.to_i - 1] if input.match?(/\A\d+\z/) && input.to_i.between?(1, candidates.length)

        puts "Not an option: '#{input}'."
      end
    rescue Interrupt
      nil
    end

    def cmd_upgrade(opts)
      name = opts[:package_name]
      return upgrade_everything(opts) unless name

      package = catalog.find(name)
      key = package ? package.name : name.downcase
      if (info = state.get_installed(key))
        exit 1 unless package ? upgrade_catalog(package, info, opts) : upgrade_recorded(key, info, opts)
        return
      end

      owner = pick_owner(name, opts)
      exit 1 unless owner && upgrade_owner(owner, opts)
    end

    # One pass over every package manager: Homebrew, the distro's packages in
    # a single transaction (repositories + AUR on Arch, which does not support
    # partial upgrades), Flatpak apps and runtimes, then release apps. Later
    # steps still run when an earlier one fails; the exit status reports it.
    def upgrade_everything(opts)
      if dry_run
        puts "==> Preview: these updates would be installed"
        return cmd_outdated(opts)
      end

      steps = [["Homebrew", -> { run_step("brew", "upgrade") }]]
      if (command = host.system_upgrade_command(interactive: opts[:interactive]))
        steps << ["System packages", -> { run_step(*command) }]
      end
      steps << ["Flatpak apps and runtimes", -> { run_step("flatpak", "update", "-y") }] if backends.fetch("flatpak").available?
      release_apps.each do |receipt, definition|
        package = Package.new({ "name" => receipt["name"] })
        steps << ["#{receipt['name']} (#{receipt['kind']})", -> { backends.fetch(receipt["kind"]).upgrade(definition, package, opts) }]
      end

      failed = steps.filter_map do |label, step|
        puts "\n==> Upgrading #{label}"
        label unless step.call
      end
      return if failed.empty?

      warn "\n✖ Failed to upgrade: #{failed.join(', ')}"
      exit 1
    end

    def upgrade_catalog(package, info, opts)
      recorded_def = info.dig("metadata", "package_definition")
      if !opts[:backend] && recorded_def && !package.has_backend?(info["backend"]) && backends[info["backend"]]
        puts "==> Upgrading #{package.display_name} via #{info['backend'].upcase} (as installed)..."
        return backends[info["backend"]].upgrade(recorded_def, package, opts)
      end

      backend_name = resolver.resolve(package, explicit_backend: opts[:backend] || info["backend"], interactive: false)
      backend = backends[backend_name]
      unless backend
        warn "Error: Backend '#{backend_name}' not available for #{package.name}."
        return false
      end

      puts "==> Upgrading #{package.display_name} via #{backend_name.upcase}..."
      backend.upgrade(package.backend(backend_name), package, opts)
    end

    # Upgrade an app installed through discovery from its saved definition.
    def upgrade_recorded(pkg_name, info, opts)
      backend = backends[info["backend"]]
      package_def = info.dig("metadata", "package_definition")
      unless backend && package_def
        warn "Error: #{pkg_name} has no usable recorded backend; reinstall it with brew app install."
        return false
      end
      package = Package.new({ "name" => pkg_name, "display_name" => info.dig("metadata", "display_name") || pkg_name })
      puts "--> Upgrading #{package.display_name} (#{info['backend']})..."
      backend.upgrade(package_def, package, opts)
    end

    def upgrade_owner(entry, opts)
      case entry.source
      when "homebrew"
        run_step("brew", "upgrade", entry.name)
      when "rpm"
        run_step("sudo", "dnf", "upgrade", *(opts[:interactive] ? [] : ["-y"]), entry.name)
      when "pacman", "aur"
        puts "==> Arch upgrades packages together; running a full system upgrade for #{entry.name}."
        run_step(*host.system_upgrade_command(interactive: opts[:interactive]))
      when "flatpak"
        run_step("flatpak", "update", "-y", entry.id)
      else
        receipt, definition = release_apps.find { |item, _| item["name"] == entry.name }
        receipt ? backends.fetch(entry.source).upgrade(definition, Package.new({ "name" => entry.name }), opts) : false
      end
    end

    # Release apps with the definition each was installed from.
    def release_apps
      host.receipts.filter_map do |receipt|
        definition = receipt["definition"] ||
                     state.get_installed(receipt["name"])&.dig("metadata", "package_definition") ||
                     catalog.find(receipt["name"])&.backend(receipt["kind"])
        [receipt, definition] if definition && backends[receipt["kind"]]
      end
    end

    # The installed package a name refers to, whichever manager owns it. With
    # several owners, ask (or require --backend when not interactive).
    def pick_owner(name, opts)
      source = opts[:backend] && { "brew" => "homebrew" }.fetch(resolver.normalize_backend(opts[:backend])) { |key| key }
      owners = host.owners(name).select { |entry| source.nil? || entry.source == source }
      if owners.empty?
        warn "Error: '#{name}' is not installed through Homebrew, #{host.platform.family == 'fedora' ? 'DNF' : 'pacman, the AUR'}, Flatpak or a release app."
        return nil
      end
      return owners.first if owners.length == 1

      puts "'#{name}' is installed more than once:"
      owners.each_with_index { |entry, index| puts "  #{index + 1}) #{SOURCE_TITLES[entry.source]}: #{entry.name} #{entry.version}" }
      unless opts[:interactive] && $stdin.tty?
        warn "Choose one with --backend=<#{owners.map(&:source).uniq.join('|')}>."
        return nil
      end
      print "Which one? [1-#{owners.length}, q = cancel]: "
      input = $stdin.gets.to_s.strip
      input.match?(/\A\d+\z/) && input.to_i.between?(1, owners.length) ? owners[input.to_i - 1] : nil
    rescue Interrupt
      nil
    end

    def run_step(*cmd)
      if dry_run
        puts "[dry-run] #{cmd.join(' ')}"
        true
      else
        puts "==> #{cmd.join(' ')}"
        system(*cmd)
      end
    end

    def cmd_uninstall(opts)
      name = opts[:package_name]
      unless name
        warn "Usage: brew app uninstall <package> [--dry-run]"
        exit 1
      end

      package = catalog.find(name)
      key = package ? package.name : name
      installed_info = state.get_installed(key)
      unless installed_info
        owners = host.owners(name)
        return uninstall_owner(name, opts) unless owners.empty?
      end

      backend_name = opts[:backend] || installed_info&.dig("backend")
      backend_name = resolver.normalize_backend(backend_name) if backend_name
      recorded_def = installed_info&.dig("metadata", "package_definition")
      # The manifest may no longer offer the backend this was installed with;
      # the definition saved at install time still identifies it.
      use_recorded = package && installed_info && recorded_def && !package.has_backend?(backend_name)
      backend_name = resolver.resolve(package, explicit_backend: backend_name, interactive: false) if package && !use_recorded

      unless backend_name && backends[backend_name]
        warn "Error: '#{name}' is not installed through any package manager brew knows about."
        exit 1
      end

      pkg_def = if package && !use_recorded
        package.backend(backend_name)
      else
        recorded_def || { "package" => key, "app_id" => key, "formula" => key }
      end
      display = package ? package.display_name : key

      puts "==> Uninstalling #{display} from #{backend_name.upcase} backend..."
      success = backends[backend_name].uninstall(pkg_def, package || Package.new({ "name" => key }), opts)

      if success
        state.record_uninstall(key) unless dry_run
        puts dry_run ? "\nRemoval preview complete for #{display}." : "\n✔ Successfully uninstalled #{display}."
      else
        exit 1
      end
    end

    # Remove a package brew app never recorded, through whichever manager owns it.
    def uninstall_owner(name, opts)
      entry = pick_owner(name, opts)
      exit 1 unless entry

      confirm = opts[:interactive] ? [] : ["--noconfirm"]
      ok = case entry.source
      when "homebrew" then run_step("brew", "uninstall", entry.name)
      when "pacman", "aur" then run_step("sudo", "pacman", "-Rs", *confirm, entry.name)
      when "rpm" then run_step("sudo", "dnf", "remove", *(opts[:interactive] ? [] : ["-y"]), entry.name)
      when "flatpak" then run_step("flatpak", "uninstall", *(opts[:interactive] ? [] : ["-y"]), entry.id)
      else backends.fetch(entry.source).uninstall({}, Package.new({ "name" => entry.name }), opts)
      end
      exit 1 unless ok
      puts dry_run ? "\nRemoval preview complete for #{entry.name}." : "\n✔ Uninstalled #{entry.name} (#{SOURCE_TITLES[entry.source]})."
    end

    def cmd_list(_opts)
      entries = host.installed
      SOURCE_TITLES.each do |source, title|
        group = entries.select { |entry| entry.source == source }.sort_by { |entry| entry.name.downcase }
        next if group.empty?

        puts "#{title} (#{group.length}):"
        group.each do |entry|
          detail = entry.id && entry.id != entry.name ? "  #{entry.id}" : ""
          puts "  #{entry.name.ljust(36)} #{entry.version}#{detail}"
        end
        puts
      end

      installed_names = entries.flat_map { |entry| [entry.name.downcase, entry.id&.downcase] }.compact
      puts "Available Catalog Packages:"
      catalog.all.each do |pkg|
        recorded = state.get_installed(pkg.name)
        status = recorded ? " [Installed: #{recorded['backend']}]" : ""
        status = " [Installed]" if status.empty? && pkg.backends.values.any? { |definition| installed_names.include?(definition["app_id"].to_s.downcase) }
        puts "  • #{pkg.name.ljust(18)} - #{pkg.display_name} (backends: #{pkg.backend_names.join(', ')})#{status}"
      end
    end

    def cmd_outdated(_opts)
      updates = host.outdated + release_updates
      if updates.empty?
        puts "Everything is up to date."
        return true
      end

      SOURCE_TITLES.each do |source, title|
        group = updates.select { |update| update.source == source }
        next if group.empty?

        puts "#{title} (#{group.length}):"
        group.each { |update| puts "  #{update.name.ljust(36)} #{[update.current, update.latest].compact.join(' -> ')}" }
        puts
      end
      true
    end

    def release_updates
      release_apps.filter_map do |receipt, definition|
        artifact = backends.fetch(receipt["kind"]).latest(definition)
        next unless artifact && artifact["url"] != receipt["url"]

        System::Update.new(source: receipt["kind"], name: receipt["name"], current: receipt["version"], latest: artifact["version"])
      end
    end

    def cmd_info(opts)
      name = opts[:package_name]
      unless name
        warn "Usage: brew app info <package>"
        exit 1
      end

      owners = host.owners(name)
      owners.each do |entry|
        puts "==> #{entry.name} #{entry.version} (installed via #{SOURCE_TITLES[entry.source]})"
        details = host.describe(entry)
        puts details unless details.empty?
        puts
      end

      package = catalog.find(name)
      return catalog_info(package, owners) if package
      return unless owners.empty?
      return if system("brew", "info", name, err: File::NULL)

      candidates = discovery.find(name)
      if candidates.empty?
        warn "Error: '#{name}' was not found in the catalog, Homebrew, Flathub, the repositories, the AUR or GitHub releases."
        exit 1
      end
      puts "#{name} is not installed. Available from:"
      candidates.each { |candidate| puts "  #{candidate.backend.upcase.ljust(8)} #{candidate.label} - #{candidate.detail}" }
    end

    def catalog_info(package, owners = [])
      installed_info = state.get_installed(package.name)
      status = if installed_info
        "Installed via #{installed_info['backend']}"
      elsif owners.any?
        "Installed via #{owners.map { |entry| SOURCE_TITLES[entry.source] }.uniq.join(', ')}"
      else
        "Not installed"
      end

      puts "=================================================="
      puts "  #{package.display_name} (#{package.name})"
      puts "=================================================="
      puts "Description: #{package.description}"
      puts "Homepage:    #{package.homepage}"
      puts "Status:      #{status}"
      puts "Default:     #{package.default_backend}"
      puts "\nAvailable Backends:"
      package.backends.each do |b_name, b_info|
        puts "  [#{b_name.upcase}]"
        puts "    Summary: #{b_info['summary']}" if b_info["summary"]
        Array(b_info["pros"]).each { |p| puts "    + #{p}" }
        Array(b_info["cons"]).each { |c| puts "    - #{c}" }
      end
      puts "=================================================="
    end

    def cmd_search(opts)
      term = opts[:package_name]
      unless term
        warn "Usage: brew app search <text>"
        exit 1
      end

      # Tick a result only when the same source has it installed.
      entries = host.installed
      installed_in = lambda do |*sources|
        entries.select { |entry| sources.include?(entry.source) }.flat_map { |entry| [entry.name.downcase, entry.id&.downcase] }.compact
      end
      installed = {
        "catalog" => catalog.all.select { |pkg| state.get_installed(pkg.name) }.map(&:name),
        "homebrew" => installed_in.call("homebrew"), "flatpak" => installed_in.call("flatpak"),
        "pacman" => installed_in.call("pacman", "aur"), "aur" => installed_in.call("pacman", "aur"), "rpm" => installed_in.call("rpm"),
      }
      matches = catalog.all.select do |pkg|
        [pkg.name, pkg.display_name, *pkg.aliases].any? { |text| text.downcase.include?(term.downcase) }
      end
      groups = { "catalog" => matches.map { |pkg| [pkg.name, "#{pkg.display_name} (backends: #{pkg.backend_names.join(', ')})"] } }
      groups.merge!(host.search(term))

      titles = { "catalog" => "Catalog" }.merge(SOURCE_TITLES)
      found = false
      groups.each do |source, results|
        next if results.empty?

        found = true
        puts "==> #{titles.fetch(source, source)}"
        results.each do |result_name, detail|
          mark = installed.fetch(source, []).include?(result_name.downcase) ? " ✔" : ""
          puts "  #{result_name}#{mark}#{detail.to_s.empty? ? '' : "  #{detail}"}"
        end
        puts
      end
      puts "No matches for '#{term}'." unless found
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
                                                  (names outside the catalog are matched exactly on
                                                  Homebrew, Flathub, pacman, AUR, then GitHub releases)
          brew app upgrade <package>              Upgrade one package via whichever manager owns it
          brew app uninstall <package>            Uninstall application
          brew app upgrade                        Upgrade everything: Homebrew, system packages
                                                  (one pacman/AUR or dnf transaction), Flatpak, release apps
          brew app list                           List packages from every package manager
          brew app outdated                       Show pending updates from every package manager
          brew app info <package>                 Show details from whichever manager owns it
          brew app search <text>                  Search catalog, Homebrew, Flathub, repositories and AUR
          brew app config [key] [value]           View or set global preferences
          brew app doctor                         Run diagnostic checks

        Backend Selection Options:
          --native                Use the host distro native backend
          --rpm, --dnf            Force Fedora RPM / DNF backend
          --pacman                Force Arch repository backend
          --aur                   Use a configured or detected AUR helper
          --flatpak               Force Flathub Flatpak backend
          --brew, --tarball       Force Homebrew formula / tarball backend
          --appimage              Use a release AppImage (manifest URL or GitHub release)
          --archive               Use a release .tar.gz/.tar.xz archive (manifest URL or GitHub release)
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
