# frozen_string_literal: true

module LinuxFormulas
  module Backends
    class Base
      attr_reader :name, :dry_run

      def initialize(dry_run: false)
        @dry_run = dry_run
      end

      def name
        raise NotImplementedError
      end

      def available?
        raise NotImplementedError
      end

      def installed?(package_def, manifest)
        raise NotImplementedError
      end

      def install(package_def, manifest, options = {})
        raise NotImplementedError
      end

      def upgrade(package_def, manifest, options = {})
        raise NotImplementedError
      end

      def uninstall(package_def, manifest, options = {})
        raise NotImplementedError
      end

      def info(package_def, manifest)
        raise NotImplementedError
      end

      protected

      def execute_command(*cmd)
        cmd_str = cmd.join(" ")
        if @dry_run
          puts "[dry-run] #{cmd_str}"
          true
        else
          puts "==> #{cmd_str}"
          system(*cmd)
        end
      end

      def command_output(*cmd)
        IO.popen(cmd, err: [:child, :out], &:read).strip
      rescue StandardError
        ""
      end

      def binary_exists?(bin)
        return File.file?(bin) && File.executable?(bin) if bin.include?(File::SEPARATOR)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          candidate = File.join(directory, bin)
          File.file?(candidate) && File.executable?(candidate)
        end
      end
    end
  end
end
