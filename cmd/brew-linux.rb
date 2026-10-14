# typed: false
# frozen_string_literal: true

require "abstract_command"
require_relative "../lib/fedora_brew/app"

module Homebrew
  module Cmd
    class Linux < AbstractCommand
      cmd_args do
        usage_banner "`linux` [<subcommand>] [<package>] [<options>]"
        description "Manage multi-backend Linux applications (RPM, Flatpak, Homebrew) - alias for `brew app`."
      end

      def run
        app = FedoraBrew::App.new
        args = ARGV.dup
        args.shift if args.first == "linux"
        app.run(args)
      end
    end
  end
end
