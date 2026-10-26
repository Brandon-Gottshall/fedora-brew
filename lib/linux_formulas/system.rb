# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "uri"

module LinuxFormulas
  # Live view of every package manager on the machine (Homebrew, pacman and
  # the AUR, dnf, Flatpak, and this tap's release apps), read straight from
  # each manager rather than from brew app's own records. Packages installed
  # through any tool (pacman, an AUR helper, Shelly, GNOME Software, ...) are
  # therefore visible to brew without being adopted first.
  class System
    Entry = Struct.new(:source, :name, :version, :id, keyword_init: true)
    Update = Struct.new(:source, :name, :current, :latest, keyword_init: true)
    RELEASE_SOURCES = %w[appimage archive].freeze

    attr_reader :platform

    # `runner` takes a command array and returns [stdout, success]; tests
    # replace it to simulate package managers.
    def initialize(platform:, aur_helper: nil, apps_dir: nil, runner: nil)
      @platform = platform
      @aur_helper = aur_helper
      @apps_dir = apps_dir
      @runner = runner || method(:capture)
    end

    def installed
      homebrew_installed + pacman_installed + rpm_installed + flatpak_installed + release_installed
    end

    def outdated
      homebrew_outdated + pacman_outdated + aur_outdated + rpm_outdated + flatpak_outdated
    end

    # Installed entries a user-typed name refers to: package name, Flatpak app
    # ID, or the last segment of an app ID (`moonlight` for
    # com.moonlight_stream.Moonlight), case-insensitively.
    # Dependencies are not listed by `installed`, so exact package names are
    # also checked against each manager's full database.
    def owners(name)
      matches = installed.select do |entry|
        [entry.name, entry.id, entry.id&.split(".")&.last].compact.any? { |candidate| candidate.casecmp?(name) }
      end
      sources = matches.map(&:source)
      matches + dependency_owners(name).reject { |entry| sources.include?(entry.source) || (sources & %w[pacman aur]).any? && %w[pacman aur].include?(entry.source) }
    end

    # The command that brings every native package (repositories and AUR on
    # Arch, all repositories on Fedora) up to date in one transaction.
    def system_upgrade_command(interactive: true)
      case platform.family
      when "arch"
        helper = aur_helper
        confirm = interactive ? [] : ["--noconfirm"]
        helper ? [helper, "-Syu", *confirm] : ["sudo", "pacman", "-Syu", *confirm]
      when "fedora"
        ["sudo", "dnf", "upgrade", "--refresh", *(interactive ? [] : ["-y"])]
      end
    end

    def aur_helper
      return @aur_helper if @aur_helper && !@aur_helper.empty?

      %w[paru yay].find do |helper|
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, helper)) }
      end
    end

    # The owning manager's own description of an installed entry.
    def describe(entry)
      cmd = case entry.source
      when "homebrew" then ["brew", "info", entry.name]
      when "pacman", "aur" then ["pacman", "-Qi", entry.name]
      when "rpm" then ["rpm", "-qi", entry.name]
      when "flatpak" then ["flatpak", "info", entry.id]
      end
      cmd ? run(*cmd).first.to_s : ""
    end

    # Name matches from each source that can install packages, grouped by
    # source, as [name, detail] pairs (at most `limit` per source).
    def search(term, limit: 10)
      results = {
        "homebrew" => lines("brew", "search", term).reject { |line| line.start_with?("==>") }.map { |name| [name, ""] },
        "flatpak" => lines("flatpak", "search", "--columns=application,name,description", term).map do |line|
          app_id, display, description = line.split("\t")
          [app_id, [display, description].compact.join(" - ")]
        end,
      }
      if platform.family == "arch"
        results["pacman"] = lines("pacman", "-Ss", term).each_slice(2).filter_map do |header, description|
          match = header.match(%r{\A(\S+)/(\S+) (\S+)})
          match && [match[2], "#{match[1]} #{match[3]} - #{description.to_s.strip}"]
        end
        results["aur"] = aur_search(term)
      elsif platform.family == "fedora"
        results["rpm"] = lines("dnf", "search", "-q", term).filter_map do |line|
          name, description = line.split(" : ", 2)
          name && description && !name.start_with?("=") ? [name.strip.sub(/\.[^.]+\z/, ""), description.strip] : nil
        end
      end
      results.transform_values { |entries| entries.first(limit) }
    end

    def receipts
      return [] unless @apps_dir && Dir.exist?(@apps_dir)

      Dir.glob(File.join(@apps_dir, "*", ".linux-formulas.json")).filter_map do |path|
        JSON.parse(File.read(path))
      rescue StandardError
        nil
      end
    end

    private

    def run(*cmd)
      @runner.call(cmd)
    end

    def capture(cmd)
      output, status = Open3.capture2({ "LC_ALL" => "C" }, *cmd, err: File::NULL)
      [output, status.success?]
    rescue StandardError
      ["", false]
    end

    def lines(*cmd, ok_statuses: nil)
      output, success = run(*cmd)
      success || ok_statuses ? output.lines.map(&:chomp).reject(&:empty?) : []
    end

    # Formulae installed on request (not dependencies) plus every cask.
    # Homebrew refuses --versions together with --installed-on-request.
    def homebrew_installed
      requested = lines("brew", "list", "--formula", "--installed-on-request")
      formulae = lines("brew", "list", "--formula", "--versions").select { |line| requested.include?(line.split.first) }
      (formulae + lines("brew", "list", "--cask", "--versions")).map do |line|
        name, *versions = line.split
        Entry.new(source: "homebrew", name: name, version: versions.last)
      end
    end

    def dependency_owners(name)
      found = []
      brew_line = lines("brew", "list", "--versions", name).first
      found << Entry.new(source: "homebrew", name: name, version: brew_line.split.last) if brew_line
      case platform.family
      when "arch"
        pacman_line = lines("pacman", "-Q", name).first
        if pacman_line
          foreign = run("pacman", "-Qm", name).last
          found << Entry.new(source: foreign ? "aur" : "pacman", name: name, version: pacman_line.split.last)
        end
      when "fedora"
        rpm_line = lines("rpm", "-q", "--qf", "%{name} %{evr}\n", name).first
        found << Entry.new(source: "rpm", name: name, version: rpm_line.split.last) if rpm_line
      end
      found
    end

    def pacman_installed
      return [] unless platform.family == "arch"

      foreign = lines("pacman", "-Qmq").to_h { |name| [name, true] }
      lines("pacman", "-Qe").map do |line|
        name, version = line.split
        Entry.new(source: foreign[name] ? "aur" : "pacman", name: name, version: version)
      end
    end

    def rpm_installed
      return [] unless platform.family == "fedora"

      lines("dnf", "repoquery", "--userinstalled", "--qf", "%{name} %{evr}\n").map do |line|
        name, version = line.split
        Entry.new(source: "rpm", name: name, version: version)
      end
    end

    def flatpak_installed
      lines("flatpak", "list", "--app", "--columns=application,name,version").map do |line|
        app_id, display, version = line.split("\t")
        Entry.new(source: "flatpak", name: display.to_s.empty? ? app_id : display, version: version.to_s, id: app_id)
      end
    end

    def release_installed
      receipts.map { |receipt| Entry.new(source: receipt["kind"], name: receipt["name"], version: receipt["version"]) }
    end

    def homebrew_outdated
      output, = run("brew", "outdated", "--json=v2")
      data = JSON.parse(output.to_s.empty? ? "{}" : output)
      (data.fetch("formulae", []) + data.fetch("casks", [])).map do |item|
        Update.new(source: "homebrew", name: item["name"], current: Array(item["installed_versions"]).last,
                   latest: item["current_version"])
      end
    rescue JSON::ParserError
      []
    end

    # `checkupdates` (pacman-contrib) reads a private copy of the sync
    # databases, so checking never needs root or risks a partial upgrade.
    def pacman_outdated
      return [] unless platform.family == "arch"

      arrow_updates("pacman", lines("checkupdates", ok_statuses: true))
    end

    def aur_outdated
      return [] unless platform.family == "arch" && (helper = aur_helper)

      arrow_updates("aur", lines(helper, "-Qua", ok_statuses: true))
    end

    def rpm_outdated
      return [] unless platform.family == "fedora"

      lines("dnf", "check-update", "-q", ok_statuses: true).filter_map do |line|
        package, version, = line.split
        next unless package&.include?(".") && version

        Update.new(source: "rpm", name: package.sub(/\.[^.]+\z/, ""), latest: version)
      end
    end

    def flatpak_outdated
      lines("flatpak", "remote-ls", "--updates", "--columns=application,version").map do |line|
        app_id, version = line.split("\t")
        Update.new(source: "flatpak", name: app_id, latest: version)
      end
    end

    def aur_search(term)
      uri = URI("https://aur.archlinux.org/rpc/v5/search/#{URI.encode_www_form_component(term)}?by=name")
      response = Net::HTTP.get_response(uri)
      return [] unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("results", []).sort_by { |result| -result["NumVotes"].to_i }.map do |result|
        [result["Name"], "AUR #{result['Version']} (#{result['NumVotes']} votes) - #{result['Description']}"]
      end
    rescue StandardError
      []
    end

    def arrow_updates(source, update_lines)
      update_lines.filter_map do |line|
        match = line.match(/\A(\S+)\s+(\S+)\s+->\s+(\S+)/)
        match && Update.new(source: source, name: match[1], current: match[2], latest: match[3])
      end
    end
  end
end
