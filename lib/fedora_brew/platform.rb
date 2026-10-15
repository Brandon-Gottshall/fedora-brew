# frozen_string_literal: true

module FedoraBrew
  # Read os-release as data, never source it as shell code.
  class Platform
    attr_reader :id, :family

    def initialize(os_release: "/etc/os-release", host_os: RUBY_PLATFORM)
      @macos = host_os.include?("darwin")
      values = {}
      if !@macos && File.file?(os_release)
        File.foreach(os_release) do |line|
          key, value = line.strip.split("=", 2)
          next unless key && value
          values[key] = value.sub(/\A["']/, "").sub(/["']\z/, "")
        end
      end
      @id = @macos ? "macos" : values.fetch("ID", "unknown")
      ids = [@id, *values.fetch("ID_LIKE", "").split]
      @family = if @macos
        "macos"
      elsif ids.any? { |id| %w[arch cachyos manjaro endeavouros].include?(id) }
        "arch"
      elsif ids.include?("fedora")
        "fedora"
      else
        @id
      end
    end

    def macos?
      @macos
    end

    def native_backend
      { "fedora" => "rpm", "arch" => "pacman" }[family]
    end
  end
end
