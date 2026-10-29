# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "rbconfig"
require "uri"

module LinuxFormulas
  # Minimal GitHub REST client for locating release downloads. Uses GITHUB_TOKEN
  # or an existing `gh` login when available to avoid anonymous rate limits.
  class Github
    API = "https://api.github.com"
    ARCH_PATTERNS = {
      "x86_64" => /x86[_-]?64|amd64|x64/i,
      "aarch64" => /aarch64|arm64/i,
    }.freeze
    OTHER_ARCH = /aarch64|arm64|armv7|armhf|i[3-6]86|ppc64|s390x|riscv/i
    ARCHIVE = /\.(tar\.gz|tgz|tar\.xz|txz|tar\.zst|tar\.bz2)\z/i

    def initialize(token: nil, arch: nil)
      @token = token
      @arch = arch || RbConfig::CONFIG["host_cpu"]
    end

    # The most-starred repository whose name is exactly `name` (case-insensitive).
    def find_repository(name)
      query = URI.encode_www_form(q: "#{name} in:name", sort: "stars", order: "desc", per_page: 20)
      items = get("/search/repositories?#{query}")&.fetch("items", []) || []
      repo = items.find { |item| item["name"].casecmp?(name) && !item["archived"] && !item["fork"] }
      repo && { "full_name" => repo["full_name"], "stars" => repo["stargazers_count"], "description" => repo["description"] }
    end

    def latest_release(repository)
      release = get("/repos/#{repository}/releases/latest")
      return nil unless release

      assets = release.fetch("assets", []).map do |asset|
        {
          "name" => asset["name"],
          "url" => asset["browser_download_url"],
          "size" => asset["size"],
          "sha256" => asset["digest"].to_s.delete_prefix("sha256:").then { |digest| digest.empty? ? nil : digest },
        }
      end
      { "tag" => release["tag_name"], "assets" => assets }
    end

    # Pick the release asset for this machine: `kind` is "appimage" or "archive".
    # A manifest-provided `pattern` (regex source) narrows the choice further.
    def select_asset(assets, kind, pattern: nil)
      matching = assets.select do |asset|
        name = asset["name"]
        next false if pattern && !Regexp.new(pattern).match?(name)
        next name.match?(/\.AppImage\z/i) if kind == "appimage"

        name.match?(ARCHIVE) && name.match?(/linux/i) && !name.match?(/\b(src|source)\b/i)
      end
      native = ARCH_PATTERNS[@arch]
      matching.find { |asset| native&.match?(asset["name"]) } ||
        matching.find { |asset| ARCH_PATTERNS.values.none? { |p| p.match?(asset["name"]) } && !asset["name"].match?(OTHER_ARCH) }
    end

    private

    def get(path)
      uri = URI("#{API}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "linux-formulas-app/1"
      request["Authorization"] = "Bearer #{token}" if token
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
        http.request(request)
      end
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      return nil if response.is_a?(Net::HTTPNotFound)

      warn "Warning: GitHub API #{path} returned #{response.code}"
      nil
    rescue StandardError => e
      warn "Warning: GitHub API request failed: #{e.message}"
      nil
    end

    def token
      return @token unless @token.nil?

      @token = ENV["GITHUB_TOKEN"].to_s.empty? ? gh_token : ENV["GITHUB_TOKEN"]
    end

    def gh_token
      output, status = Open3.capture2("gh", "auth", "token", err: File::NULL)
      status.success? && !output.strip.empty? ? output.strip : false
    rescue StandardError
      false
    end
  end
end
