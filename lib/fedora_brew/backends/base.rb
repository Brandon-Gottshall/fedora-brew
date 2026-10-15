# frozen_string_literal: true

module FedoraBrew
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
        system("command -v #{bin} >/dev/null 2>&1")
      end
    end
  end
end
