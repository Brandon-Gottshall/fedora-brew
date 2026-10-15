# frozen_string_literal: true

require "yaml"
require "date"
require_relative "platform"

module LinuxFormulas
  class Package
    attr_reader :name, :display_name, :description, :homepage, :default_backend, :backends

    def initialize(data, platform: Platform.new)
      @name = data.fetch("name")
      @display_name = data["display_name"] || @name.capitalize
      @description = data["description"] || ""
      @homepage = data["homepage"] || ""
      section = platform.macos? ? data.fetch("macos", {}) : data.fetch("distros", {}).fetch(platform.family, {})
      shared = platform.macos? ? {} : data.fetch("backends", {})
      @backends = shared.merge(section.fetch("backends", {}))
      preferred = section["default"] || data["default"]
      @default_backend = @backends.key?(preferred) ? preferred : @backends.keys.first
    end

    def backend_names
      backends.keys
    end

    def backend(name)
      backends[name.to_s]
    end

    def has_backend?(name)
      backends.key?(name.to_s)
    end
  end

  class Catalog
    attr_reader :packages_dir

    def initialize(packages_dir: nil, platform: Platform.new)
      @platform = platform
      @packages_dir = packages_dir || File.expand_path("../../packages", __dir__)
    end

    def all
      Dir.glob(File.join(@packages_dir, "*.{yaml,yml}")).map do |file|
        load_file(file)
      end.compact.sort_by(&:name)
    end

    def find(name)
      target = name.to_s.downcase.strip
      file = File.join(@packages_dir, "#{target}.yaml")
      file = File.join(@packages_dir, "#{target}.yml") unless File.exist?(file)
      return nil unless File.exist?(file)

      load_file(file)
    end

    private

    def load_file(path)
      data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time])
      return nil unless data.is_a?(Hash) && data["name"]

      Package.new(data, platform: @platform)
    rescue StandardError => e
      warn "Warning: Failed to load manifest #{path}: #{e.message}"
      nil
    end
  end
end
