# frozen_string_literal: true

require "json"
require "fileutils"

module FedoraBrew
  class State
    attr_reader :config_dir, :config_file, :state_file

    def initialize(config_dir: nil)
      base_dir = config_dir ||
                 ENV["HOMEBREW_FEDORA_BREW_CONFIG_DIR"] ||
                 ENV["FEDORA_BREW_CONFIG_DIR"] ||
                 File.join(ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config"), "fedora-brew")
      @config_dir = File.expand_path(base_dir)
      @config_file = File.join(@config_dir, "config.json")
      @state_file = File.join(@config_dir, "installed.json")
      ensure_dirs!
    end

    def config
      @config ||= load_json(@config_file, default: { "default_backend" => nil, "auto_confirm" => false })
    end

    def set_config(key, value)
      cfg = config
      cfg[key.to_s] = value
      save_json(@config_file, cfg)
      @config = cfg
    end

    def installed
      @installed ||= load_json(@state_file, default: {})
    end

    def get_installed(package_name)
      installed[package_name.to_s]
    end

    def record_install(package_name, backend_name, metadata: {})
      data = installed
      data[package_name.to_s] = {
        "backend" => backend_name.to_s,
        "installed_at" => Time.now.utc.iso8601,
        "metadata" => metadata,
      }
      save_json(@state_file, data)
      @installed = data
    end

    def record_uninstall(package_name)
      data = installed
      data.delete(package_name.to_s)
      save_json(@state_file, data)
      @installed = data
    end

    private

    def ensure_dirs!
      FileUtils.mkdir_p(@config_dir) unless Dir.exist?(@config_dir)
    end

    def load_json(path, default:)
      return default unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue StandardError => e
      warn "Warning: Failed to parse #{path}: #{e.message}"
      default
    end

    def save_json(path, data)
      ensure_dirs!
      File.write(path, JSON.pretty_generate(data))
    end
  end
end
