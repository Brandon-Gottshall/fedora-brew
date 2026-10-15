# frozen_string_literal: true

module LinuxFormulas
  class Resolver
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

    def prompt_user(package)
      puts "\n#{package.display_name} has multiple Linux backends available:\n\n"

      backends = package.backends
      indexed_keys = backends.keys

      default_key = package.default_backend || indexed_keys.first
      default_index = indexed_keys.index(default_key) ? indexed_keys.index(default_key) + 1 : 1

      indexed_keys.each_with_index do |key, idx|
        info = backends[key]
        is_default = (key == default_key)
        tag = is_default ? " (recommended/default)" : ""

        puts "  #{idx + 1}) #{key.upcase}#{tag}"
        puts "     Summary: #{info['summary']}" if info["summary"]
        if info["pros"] && !info["pros"].empty?
          info["pros"].each { |pro| puts "     • [Pro] #{pro}" }
        end
        if info["cons"] && !info["cons"].empty?
          info["cons"].each { |con| puts "     • [Con] #{con}" }
        end
        puts ""
      end

      print "Choose installation method [1-#{indexed_keys.length}] (default: #{default_index}): "
      input = $stdin.gets&.strip

      if input.nil? || input.empty?
        return default_key
      end

      if input =~ /^\d+$/
        num = input.to_i
        if num >= 1 && num <= indexed_keys.length
          return indexed_keys[num - 1]
        end
      end

      normalized = normalize_backend(input)
      if package.has_backend?(normalized)
        return normalized
      end

      puts "Invalid choice '#{input}', using default: #{default_key}"
      default_key
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
