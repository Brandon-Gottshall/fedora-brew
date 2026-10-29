# frozen_string_literal: true

module LinuxFormulas
  class Resolver
    # Raised when the user declines the backend prompt; nothing is installed.
    class Cancelled < StandardError; end

    SYNONYMS = {
      "dnf" => "rpm",
      "tarball" => "brew",
      "cask" => "brew",
      "flathub" => "flatpak",
    }.freeze

    attr_reader :state

    def initialize(state: nil)
      @state = state || State.new
    end

    def resolve(package, explicit_backend: nil, interactive: true)
      available = package.backend_names
      if available.empty?
        raise "Package '#{package.name}' does not define any backends."
      end

      # 1. Explicit CLI flag
      if explicit_backend && !explicit_backend.empty?
        normalized = normalize_backend(explicit_backend)
        unless package.has_backend?(normalized)
          raise "Backend '#{explicit_backend}' is not supported for #{package.display_name}. Available: #{available.join(', ')}"
        end
        return normalized
      end

      # 2. Configured global preference if valid for this package
      configured = normalize_backend(state.config["default_backend"])
      if configured && package.has_backend?(configured) && (!interactive || !tty?)
        return configured
      end

      return available.first if available.length == 1

      # 3. Interactive prompt if in terminal
      if interactive && tty?
        choice = prompt_user(package)
        return choice if choice
      end

      # 4. Non-interactive fallback
      fallback(package)
    end

    def normalize_backend(name)
      clean = name.to_s.downcase.strip.sub(/^--/, "")
      return state.platform.native_backend || "native" if clean == "native"

      SYNONYMS[clean] || clean
    end

    private

    def tty?
      $stdin.tty? && $stdout.tty?
    end

    # Lists the recommended backend first. Enter picks it; q, n, cancel or
    # end-of-input cancels; anything unrecognised asks again.
    def prompt_user(package)
      default_key = package.default_backend || package.backend_names.first
      keys = [default_key, *(package.backend_names - [default_key])]
      puts "\n#{package.display_name} has multiple Linux backends available:\n\n"
      keys.each_with_index do |key, idx|
        info = package.backend(key)
        puts "  #{idx + 1}) #{key.upcase}#{key == default_key ? ' (recommended)' : ''}"
        puts "     Summary: #{info['summary']}" if info["summary"]
        Array(info["pros"]).each { |pro| puts "     • [Pro] #{pro}" }
        Array(info["cons"]).each { |con| puts "     • [Con] #{con}" }
        puts ""
      end

      loop do
        print "Choose installation method [1-#{keys.length}, Enter = 1, q = cancel]: "
        input = $stdin.gets
        raise Cancelled if input.nil?

        input = input.strip.downcase
        return default_key if input.empty?
        raise Cancelled if %w[q quit n no cancel].include?(input)
        return keys[input.to_i - 1] if input.match?(/\A\d+\z/) && input.to_i.between?(1, keys.length)

        normalized = normalize_backend(input)
        return normalized if package.has_backend?(normalized)

        puts "Not an option: '#{input}'."
      end
    rescue Interrupt
      raise Cancelled
    end

    def fallback(package)
      # Check package default
      if package.default_backend && package.has_backend?(package.default_backend)
        return package.default_backend
      end

      # Auto-detect distribution
      native = state.platform.native_backend
      return native if native && package.has_backend?(native)

      if package.has_backend?("flatpak")
        return "flatpak"
      end

      package.backend_names.first
    end
  end
end
