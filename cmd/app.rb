# typed: false
# frozen_string_literal: true

require_relative "../lib/linux_formulas/app"

module Homebrew
  module Cmd
    class App < AbstractCommand
      cmd_args do
        usage_banner "`app` [<subcommand>] [<package>] [<options>]"
        description "Manage multi-backend Linux applications (RPM, Flatpak, Homebrew)."
      end

      def run
        app = LinuxFormulas::App.new
        # Forward remaining arguments after 'app'
        args = ARGV.dup
        args.shift if args.first == "app"
        app.run(args)
      end
    end
  end
end
