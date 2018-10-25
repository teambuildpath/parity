require "parity/backup"

module Parity
  class Environment
    def initialize(environment, subcommands, app_argument: "--remote")
      self.environment = environment
      self.subcommand = subcommands[0]
      self.arguments = subcommands[1..-1]
      self.app_argument = app_argument
    end

    def run
      run_command || false
    end

    private

    PROTECTED_ENVIRONMENTS = %w(development production)

    attr_accessor :app_argument, :environment, :subcommand, :arguments

    def run_command
      if self.class.private_method_defined?(methodized_subcommand)
        send(methodized_subcommand)
      else
        run_via_cli
      end
    end

    def open
      run_via_cli
    end

    def run_via_cli
      Kernel.exec("heroku", subcommand, *arguments, app_argument, environment)
    end

    def backup
      Kernel.system("heroku pg:backups:capture #{app_argument} #{environment}")
    end

    def deploy
      if production?
        Kernel.system("git push production master")
      else
        Kernel.system(
          "git push #{environment} HEAD:master --force",
        )
      end
    end

    def quick_restore
      if production? && !forced?
        $stdout.puts "Piss Off! You can only do this on development."
      else
        Backup.new(
          from: arguments.first,
          to: environment,
          additional_args: additional_restore_arguments,
        ).quick_restore
      end
    end

    def restore
      if production? && !forced?
        $stdout.puts "Parity does not support restoring backups into your "\
          "production environment. Use `--force` to override."
      else
        Backup.new(
          from: arguments.first,
          to: environment,
          additional_args: additional_restore_arguments,
        ).restore
      end
    end

    alias :restore_from :restore

    def production?
      environment == "production"
    end

    def forced?
      arguments.include?("--force")
    end

    def additional_restore_arguments
      (arguments.drop(1) - ["--force"] + [restore_confirmation_argument]).
        compact.
        join(" ")
    end

    def restore_confirmation_argument
      unless PROTECTED_ENVIRONMENTS.include?(environment) || from_development?
        "--confirm #{heroku_app_name}"
      end
    end

    def from_development?
      arguments.first == "development"
    end

    def console
      Kernel.system(command_for_remote("run rails console"))
    end

    def migrate
      Kernel.system(%{
        #{command_for_remote('run rake db:migrate')} &&
        #{command_for_remote('restart')}
      })
    end

    def tail
      Kernel.system(
        command_for_remote("logs --tail #{arguments.join(' ')}"),
      )
    end

    def redis_cli
      Kernel.system("redis-cli", "-u", raw_redis_url)
    end

    def raw_redis_url
      @redis_to_go_url ||= Open3.
        capture3(command_for_remote("config:get REDIS_URL"))[0].
        strip
    end

    def heroku_app_name
      HerokuAppName.new(environment).to_s
    end

    def command_for_remote(command)
      "heroku #{command} #{app_argument} #{environment}"
    end

    def methodized_subcommand
      subcommand.gsub("-", "_").to_sym
    end
  end
end
