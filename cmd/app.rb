# typed: false
# frozen_string_literal: true

require_relative "../lib/fedora_brew/app"

module Homebrew
  module Cmd
    class App < AbstractCommand
      cmd_args do
        usage_banner "`app` [<subcommand>] [<package>] [<options>]"
        description "Manage multi-backend Linux applications (RPM, Flatpak, Homebrew)."
      end

      def run
        app = FedoraBrew::App.new
        # Forward remaining arguments after 'app'
        args = ARGV.dup
        args.shift if args.first == "app"
        app.run(args)
      end
    end
  end
end
