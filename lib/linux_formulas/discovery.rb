# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "uri"
require_relative "github"

module LinuxFormulas
  # Finds exact-name matches for a package that is not in the catalog.
  # `homebrew_match` checks for a formula or Linux-installable cask; `find`
  # searches Flathub, pacman repositories and the AUR in that order, then
  # GitHub release AppImages and archives only when nothing earlier matched.
  # Nothing here installs anything; the caller confirms a candidate.
  class Discovery
    ORDER = %w[flatpak pacman aur].freeze
    MACOS_ONLY_ARTIFACTS = %w[app pkg installer prefpane qlplugin mdimporter screen_saver service suite vst_plugin vst3_plugin au_plugin].freeze
    RELEASE_KINDS = %w[appimage archive].freeze
    Candidate = Struct.new(:backend, :package_def, :label, :detail, keyword_init: true)

    def initialize(backends:, github: Github.new)
      @backends = backends
      @github = github
    end

    def find(name, only: nil)
      candidates = ORDER.flat_map do |backend|
        next [] if only && only != backend
        next [] unless @backends[backend]&.available?

        Array(send("probe_#{backend}", name))
      end
      return candidates unless candidates.empty?
      return [] if only && !RELEASE_KINDS.include?(only)

      probe_github(name, only)
    end

    def homebrew_match(name)
      probe_brew(name).first
    end

    private

    def capture(*cmd)
      output, status = Open3.capture2({ "LC_ALL" => "C" }, *cmd, err: File::NULL)
      status.success? ? output : nil
    rescue StandardError
      nil
    end

    def probe_brew(name)
      json = capture("brew", "info", "--json=v2", name)
      data = json && JSON.parse(json)
      return [] unless data

      formula = data.fetch("formulae", []).first
      cask = data.fetch("casks", []).find { |entry| linux_cask?(entry) }
      if formula
        version = formula.dig("versions", "stable")
        [Candidate.new(backend: "brew", package_def: { "formula" => formula["full_name"] },
                       label: formula["full_name"], detail: "Homebrew formula #{version} - #{formula['desc']}")]
      elsif cask
        [Candidate.new(backend: "brew", package_def: { "cask" => cask["full_token"] || cask["token"] },
                       label: cask["full_token"] || cask["token"], detail: "Homebrew cask #{cask['version']} - #{cask['desc']}")]
      else
        []
      end
    rescue JSON::ParserError
      []
    end

    def linux_cask?(cask)
      return false if cask.dig("depends_on", "macos")

      cask.fetch("artifacts", []).none? { |artifact| artifact.is_a?(Hash) && (artifact.keys & MACOS_ONLY_ARTIFACTS).any? }
    end

    def probe_flatpak(name)
      output = capture("flatpak", "search", "--columns=application,name,version,remotes", name)
      return [] unless output

      output.lines.filter_map do |line|
        app_id, display, version, remotes = line.chomp.split("\t")
        next unless app_id && remotes
        next unless app_id.casecmp?(name) || app_id.split(".").last.casecmp?(name) || display.to_s.casecmp?(name)

        Candidate.new(backend: "flatpak", package_def: { "app_id" => app_id, "remote" => remotes.split(",").first },
                      label: display.to_s.empty? ? app_id : display, detail: "Flatpak #{app_id} #{version} (#{remotes})".squeeze(" "))
      end
    end

    def probe_pacman(name)
      output = capture("pacman", "-Si", name)
      return [] unless output

      fields = output.lines.filter_map { |line| line.split(/\s+:\s+/, 2).map(&:strip) if line.include?(" : ") }.to_h
      [Candidate.new(backend: "pacman", package_def: { "package" => name }, label: name,
                     detail: "#{fields['Repository']} repository #{fields['Version']} - #{fields['Description']}")]
    end

    def probe_aur(name)
      uri = URI("https://aur.archlinux.org/rpc/v5/info?#{URI.encode_www_form('arg[]' => name)}")
      response = Net::HTTP.get_response(uri)
      return [] unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body).fetch("results", []).find { |entry| entry["Name"] == name }
      return [] unless result

      flags = ["#{result['NumVotes']} votes", "maintainer #{result['Maintainer'] || 'none (orphaned)'}"]
      flags << "flagged out of date" if result["OutOfDate"]
      [Candidate.new(backend: "aur", package_def: { "package" => name }, label: name,
                     detail: "AUR #{result['Version']} (#{flags.join(', ')}) - #{result['Description']}")]
    rescue StandardError
      []
    end

    def probe_github(name, only)
      repository = @github.find_repository(name)
      release = repository && @github.latest_release(repository["full_name"])
      return [] unless release

      RELEASE_KINDS.filter_map do |kind|
        next if only && only != kind
        next unless @backends[kind]&.available?

        asset = @github.select_asset(release["assets"], kind)
        next unless asset

        checksum = asset["sha256"] ? "SHA-256 published" : "no published checksum"
        Candidate.new(
          backend: kind, package_def: { "github" => repository["full_name"] }, label: repository["full_name"],
          detail: "GitHub release #{release['tag']}: #{asset['name']} (#{repository['stars']} stars, #{checksum}, unreviewed)",
        )
      end
    end
  end
end
